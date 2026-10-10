part of '../widget_rebuilds_inspector.dart';

const int _eventLimit = 50;
const int _timestampLimit = 120;
const int _sparklineBuckets = 12;
const int _flashLimit = 24;
const Duration _flashDuration = Duration(milliseconds: 650);

/// Collects rebuild counts, baselines, and exported reports.
///
/// A [WidgetRebuildInspector] applies its settings to the controller it uses.
/// In-app switches update the controller directly and stay in effect until the
/// matching widget setting changes.
///
/// The controller is inert until a [RebuildInspector] or [WidgetRebuildInspector]
/// mounts it. Release builds never install Flutter's rebuild hook.
class RebuildInspectorController extends ChangeNotifier {
  /// Creates a controller. Prefer passing it to [WidgetRebuildInspector].
  RebuildInspectorController({
    this.onFrequentRebuild,
    RebuildThresholds thresholds = const RebuildThresholds(),
    bool automaticTracking = false,
    bool userWidgetsOnly = true,
    bool ignoreCommonWidgets = true,
    bool highlightHotspots = false,
  }) : _thresholds = thresholds,
       _automaticTracking = automaticTracking,
       _userWidgetsOnly = userWidgetsOnly,
       _ignoreCommonWidgets = ignoreCommonWidgets,
       _highlightHotspots = highlightHotspots;

  /// The controller used when a [RebuildInspector] has no ancestor
  /// [WidgetRebuildInspector] and no explicit controller.
  static RebuildInspectorController get instance =>
      _instance ??= RebuildInspectorController();
  static RebuildInspectorController? _instance;

  /// Drops [instance] so tests do not share counts.
  @visibleForTesting
  static void debugResetInstance() {
    final current = _instance;
    if (current != null) {
      current.reset();
      current._forceDetach();
    }
    _instance = null;
  }

  /// Called after a row first enters [RebuildBand.frequent].
  ///
  /// Invoked after the frame, so the callback may call [State.setState].
  void Function(RebuildWidgetStats stats)? onFrequentRebuild;

  RebuildThresholds _thresholds;
  bool _automaticTracking;
  bool _userWidgetsOnly;
  bool _ignoreCommonWidgets;
  bool _highlightHotspots;
  bool _paused = false;
  bool _enabled = true;
  bool _disposed = false;
  bool _changed = false;
  bool _endFrameScheduled = false;
  bool _flashTicking = false;
  int? _flashTickId;
  int _attachments = 0;

  final Map<String, _Entry> _entries = {};
  final List<RebuildEvent> _events = [];
  final Set<_RebuildMonitorElement> _monitors = {};
  final Set<Element> _seenThisFrame = {};
  final Set<String> _pinned = {};
  // Flutter only advances `builtOnce` while debugPrintRebuildDirtyWidgets is
  // set, so remember each element ourselves. Expando does not retain it.
  final Expando<bool> _sawBuild = Expando<bool>();
  final List<_FlashMark> _flashes = [];
  final List<String> _pendingAlerts = [];

  _Baseline? _baseline;
  _RenderFlashLayer? _flashLayer;

  /// Count and rate cutoffs for [RebuildBand].
  RebuildThresholds get thresholds => _thresholds;

  /// Updates [thresholds] and refreshes listeners.
  set thresholds(RebuildThresholds value) {
    if (_thresholds == value) return;
    _thresholds = value;
    _notifySoon();
  }

  /// Whether widgets that are not wrapped in [RebuildInspector] are recorded.
  ///
  /// Automatic rows group every instance of a runtime type. They count rebuilds
  /// after the first mount, not the mount itself.
  bool get automaticTracking => _automaticTracking;

  /// Enables or disables automatic detection.
  set automaticTracking(bool value) {
    if (_automaticTracking == value) return;
    _automaticTracking = value;
    _notifySoon();
  }

  /// When true, automatic mode keeps widgets created in the app project.
  bool get userWidgetsOnly => _userWidgetsOnly;

  /// Updates [userWidgetsOnly].
  set userWidgetsOnly(bool value) {
    if (_userWidgetsOnly == value) return;
    _userWidgetsOnly = value;
    _notifySoon();
  }

  /// When true, automatic mode hides common layout and Material widgets.
  bool get ignoreCommonWidgets => _ignoreCommonWidgets;

  /// Updates [ignoreCommonWidgets].
  set ignoreCommonWidgets(bool value) {
    if (_ignoreCommonWidgets == value) return;
    _ignoreCommonWidgets = value;
    _notifySoon();
  }

  /// When true, automatic widgets in [RebuildBand.frequent] flash on screen.
  bool get highlightHotspots => _highlightHotspots;

  /// Updates [highlightHotspots].
  set highlightHotspots(bool value) {
    if (_highlightHotspots == value) return;
    _highlightHotspots = value;
    _notifySoon();
  }

  /// When true, new builds are ignored and existing counts stay put.
  bool get paused => _paused;

  /// Pauses or resumes recording.
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    _notifySoon();
  }

  /// When false, this controller ignores builds.
  bool get enabled => _enabled;

  /// Enables or disables recording for this controller.
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _notifySoon();
  }

  /// Whether Flutter's debug rebuild hook currently points at this package.
  ///
  /// False in release and profile builds, and false when another tool replaced
  /// the hook. Parent-driven [RebuildInspector] counts still work without it.
  bool get hookConnected => _HookRegistry.instance.ownsHook;

  /// Whether Flutter was compiled with widget creation locations.
  ///
  /// Automatic filtering uses this to tell app widgets from framework widgets.
  bool get creationTrackingAvailable =>
      WidgetInspectorService.instance.isWidgetCreationTracked();

  /// Current rows, busiest first.
  List<RebuildWidgetStats> get stats {
    _forgetInspectorRows();
    final rows = _entries.values.map(_snapshotOf).toList()
      ..sort((a, b) {
        final byCount = b.buildCount.compareTo(a.buildCount);
        if (byCount != 0) return byCount;
        return a.name.compareTo(b.name);
      });
    return List.unmodifiable(rows);
  }

  /// Recent build events, oldest first.
  List<RebuildEvent> get events {
    _forgetInspectorRows();
    return List.unmodifiable(_events);
  }

  /// Whether [markBaseline] has been called since [clearBaseline].
  bool get hasBaseline => _baseline != null;

  /// Label of the current baseline, or null.
  String? get baselineLabel => _baseline?.label;

  /// Snapshot for [id], if it has been recorded.
  RebuildWidgetStats? statsFor(String id) {
    final entry = _entries[id];
    if (entry == null) return null;
    return _snapshotOf(entry);
  }

  /// Whether an automatic row should flash.
  bool isPinned(String id) => _pinned.contains(id);

  /// Flashes an automatic widget type whenever it rebuilds.
  void pin(String id) {
    if (_pinned.add(id)) _notifySoon();
  }

  /// Stops flashing a row that was [pin]ned.
  void unpin(String id) {
    if (_pinned.remove(id)) _notifySoon();
  }

  /// Zeros counts and the timeline. Instrumented names stay so the dashboard
  /// does not go blank. The baseline is kept.
  void reset() {
    final automatic = <String>[];
    for (final entry in _entries.entries) {
      if (entry.value.source == RebuildSource.automatic) {
        automatic.add(entry.key);
        continue;
      }
      entry.value.clearCounts();
    }
    for (final id in automatic) {
      _entries.remove(id);
    }
    _events.clear();
    _pendingAlerts.clear();
    for (final monitor in _monitors) {
      monitor.syncVisuals(flash: false);
    }
    _notifySoon();
  }

  /// Stores the current counts so later builds can be compared with them.
  void markBaseline([String label = 'Baseline']) {
    _baseline = _Baseline(
      label: label,
      capturedAt: DateTime.now(),
      counts: {
        for (final entry in _entries.entries) entry.key: entry.value.buildCount,
      },
      names: {
        for (final entry in _entries.entries) entry.key: entry.value.name,
      },
    );
    _notifySoon();
  }

  /// Drops the baseline captured by [markBaseline].
  void clearBaseline() {
    if (_baseline == null) return;
    _baseline = null;
    _notifySoon();
  }

  /// Compares current counts with the last [markBaseline], or null if there is none.
  RebuildComparison? compareToBaseline() {
    final baseline = _baseline;
    if (baseline == null) return null;
    final ids = {...baseline.counts.keys, ..._entries.keys};
    final deltas = <RebuildDelta>[
      for (final id in ids)
        if (_entries[id] != null || baseline.counts.containsKey(id))
          RebuildDelta(
            id: id,
            name: _entries[id]?.name ?? baseline.names[id] ?? id,
            before: baseline.counts[id],
            after: _entries[id]?.buildCount ?? 0,
          ),
    ]..sort((a, b) => b.change.abs().compareTo(a.change.abs()));
    return RebuildComparison(
      label: baseline.label,
      capturedAt: baseline.capturedAt,
      deltas: deltas,
    );
  }

  /// JSON report, including the baseline when one exists.
  String exportJson() {
    final comparison = compareToBaseline();
    final payload = <String, Object?>{
      'generatedAt': DateTime.now().toIso8601String(),
      'disclaimer': rebuildInspectorDisclaimer,
      'thresholds': {
        'moderateAfter': _thresholds.moderateAfter,
        'frequentAfter': _thresholds.frequentAfter,
        'moderatePerSecond': _thresholds.moderatePerSecond,
        'frequentPerSecond': _thresholds.frequentPerSecond,
        'rateWindowMs': _thresholds.rateWindow.inMilliseconds,
      },
      'widgets': [for (final row in stats) _statsJson(row)],
      'events': [
        for (final event in _events)
          {
            'name': event.name,
            'source': event.source.name,
            'cause': event.cause.name,
            'occurredAt': event.occurredAt.toIso8601String(),
          },
      ],
      if (comparison != null)
        'baseline': {
          'label': comparison.label,
          'capturedAt': comparison.capturedAt.toIso8601String(),
          'deltas': [
            for (final delta in comparison.deltas)
              {
                'name': delta.name,
                'before': delta.before,
                'after': delta.after,
                'change': delta.change,
              },
          ],
        },
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Markdown report suitable for a pull request or a notebook.
  String exportMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Widget rebuild report')
      ..writeln()
      ..writeln(rebuildInspectorDisclaimer)
      ..writeln()
      ..writeln(
        '| Widget | Source | Builds | Parent | Child | Per second | Band | Vs baseline |',
      )
      ..writeln('| --- | --- | ---: | ---: | ---: | ---: | --- | ---: |');
    for (final row in stats) {
      final delta = row.deltaFromBaseline;
      final versus = !hasBaseline
          ? ''
          : delta == null
          ? 'new'
          : delta > 0
          ? '+$delta'
          : '$delta';
      buffer.writeln(
        '| ${_cell(row.name)} | ${row.source.label} | ${row.buildCount} | '
        '${row.parentRebuildCount} | ${row.childRebuildCount} | '
        '${row.buildsPerSecond.toStringAsFixed(1)} | ${row.band.label} | $versus |',
      );
    }
    final comparison = compareToBaseline();
    if (comparison != null) {
      buffer
        ..writeln()
        ..writeln(
          'Baseline "${_cell(comparison.label)}" captured at ${comparison.capturedAt.toIso8601String()}.',
        );
    }
    return buffer.toString();
  }

  /// Registers a mounted inspector. Public callers should use the widgets.
  void _attach() {
    _attachments += 1;
    if (_attachments == 1) _HookRegistry.instance.add(this);
  }

  /// Releases a registration created by [_attach].
  void _detach() {
    if (_attachments == 0) return;
    _attachments -= 1;
    if (_attachments == 0) {
      _HookRegistry.instance.remove(this);
      _stopFlashTick();
    }
  }

  void _forceDetach() {
    _attachments = 0;
    _monitors.clear();
    _HookRegistry.instance.remove(this);
    _stopFlashTick();
  }

  void _registerMonitor(_RebuildMonitorElement element) {
    if (_monitors.add(element)) _attach();
  }

  void _unregisterMonitor(_RebuildMonitorElement element) {
    element.rebuiltThisFrame = false;
    if (_monitors.remove(element)) _detach();
  }

  void _recordBoundary(_RebuildMonitorElement element) {
    if (!_enabled || _paused || _disposed) return;
    final cause = element.hasRecordedBuild
        ? RebuildCause.parentRebuild
        : RebuildCause.initialBuild;
    element.hasRecordedBuild = true;
    _bump(
      id: element.statsId,
      name: element.widget.name,
      location: element.widget.location,
      source: RebuildSource.instrumented,
      cause: cause,
    );
  }

  void _recordChild(_RebuildMonitorElement element) {
    if (!_enabled || _paused || _disposed || !element.hasRecordedBuild) return;
    _bump(
      id: element.statsId,
      name: element.widget.name,
      location: element.widget.location,
      source: RebuildSource.instrumented,
      cause: RebuildCause.childRebuild,
    );
  }

  void _handleRebuild(Element element, bool builtOnce) {
    if (_disposed || !_enabled || _paused || _attachments == 0) return;
    if (element.debugIsDefunct) return;
    // The overlay refreshes whenever counts change. Recording that refresh
    // schedules another refresh, so the panel's own widgets are ignored.
    // Wrapped app widgets sit under a monitor, not under the panel, and still
    // need to be counted.
    if (_isInspectorChrome(element)) return;

    _seenThisFrame.add(element);
    _scheduleEndFrame();

    if (element is _RebuildMonitorElement) return;

    Element? parent;
    element.visitAncestorElements((ancestor) {
      parent = ancestor;
      return false;
    });

    if (parent is _RebuildMonitorElement) {
      final monitor = parent! as _RebuildMonitorElement;
      if (!identical(monitor.widget.controller, this)) return;
      // `builtOnce` is false only for this element's first build. The slot flag
      // is set before children update, so a parent rebuild is not also a child
      // rebuild. An identical (const) child never reaches this hook.
      if (!builtOnce && !monitor.hasRecordedBuild) {
        _recordBoundary(monitor);
        monitor.syncVisuals(flash: false);
      } else if (monitor.rebuiltThisFrame) {
        final flash =
            monitor.hasRecordedBuild && monitor.widget.highlightRebuilds;
        _recordBoundary(monitor);
        monitor.syncVisuals(flash: flash);
      } else {
        _recordChild(monitor);
        monitor.syncVisuals(flash: monitor.widget.highlightRebuilds);
      }
      return;
    }

    // `builtOnce` stays false unless rebuild printing is enabled, so the
    // expando is the source of truth for "this element has built before".
    final subsequent = builtOnce || (_sawBuild[element] ?? false);
    _sawBuild[element] = true;
    if (!_automaticTracking || !subsequent) return;
    if (_underMonitor(element)) return;

    final widget = element.widget;
    if (!_includeAutomaticWidget(
      widget,
      userWidgetsOnly: _userWidgetsOnly,
      ignoreCommonWidgets: _ignoreCommonWidgets,
      creationTracked: creationTrackingAvailable,
    )) {
      return;
    }

    final parentRebuilt = parent != null && _seenThisFrame.contains(parent);
    final typeName = widget.runtimeType.toString();
    final id = 'auto:$typeName';
    _bump(
      id: id,
      name: typeName,
      location: null,
      source: RebuildSource.automatic,
      cause: parentRebuilt
          ? RebuildCause.parentRebuild
          : RebuildCause.childRebuild,
    );
    _maybeFlashAutomatic(element, id);
  }

  bool _isInspectorChrome(Element element) {
    if (_inspectorWidgetNames.contains(element.widget.runtimeType.toString())) {
      return true;
    }
    var found = false;
    element.visitAncestorElements((ancestor) {
      final name = ancestor.widget.runtimeType.toString();
      if (ancestor.widget is _InspectorChrome ||
          ancestor.widget is _RebuildOverlay ||
          _inspectorWidgetNames.contains(name)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool _underMonitor(Element element) {
    var found = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor is _RebuildMonitorElement) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  void _forgetInspectorRows() {
    _entries.removeWhere(
      (_, entry) => _inspectorWidgetNames.contains(entry.name),
    );
    _events.removeWhere((event) => _inspectorWidgetNames.contains(event.name));
    _pinned.removeWhere(
      (id) =>
          id.startsWith('auto:') &&
          _inspectorWidgetNames.contains(id.substring(5)),
    );
  }

  void _bump({
    required String id,
    required String name,
    required String? location,
    required RebuildSource source,
    required RebuildCause cause,
  }) {
    final entry = _entries.putIfAbsent(
      id,
      () => _Entry(id: id, name: name, source: source),
    );
    entry.name = name;
    if (location != null) entry.location = location;
    entry.buildCount += 1;
    switch (cause) {
      case RebuildCause.initialBuild:
        entry.initialBuildCount += 1;
      case RebuildCause.parentRebuild:
        entry.parentRebuildCount += 1;
      case RebuildCause.childRebuild:
        entry.childRebuildCount += 1;
    }
    entry.lastCause = cause;
    entry.touch();
    _events.add(
      RebuildEvent(
        name: name,
        source: source,
        cause: cause,
        occurredAt: entry.lastBuildAt!,
      ),
    );
    if (_events.length > _eventLimit) _events.removeAt(0);
    final band = _bandFor(entry);
    if (band == RebuildBand.frequent &&
        entry.notifiedBand != RebuildBand.frequent) {
      _pendingAlerts.add(id);
    }
    entry.notifiedBand = band;
    _changed = true;
    _scheduleEndFrame();
  }

  void _maybeFlashAutomatic(Element element, String id) {
    final entry = _entries[id];
    if (entry == null) return;
    final band = _bandFor(entry);
    final pinned = _pinned.contains(id);
    if (!pinned && !(_highlightHotspots && band == RebuildBand.frequent)) {
      return;
    }
    final rect = _globalRect(element);
    if (rect == null || rect.isEmpty) return;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final view = views.first;
      final screen = view.physicalSize / view.devicePixelRatio;
      if (rect.width > screen.width * 0.92 &&
          rect.height > screen.height * 0.92) {
        return;
      }
    }
    _flashes.add(
      _FlashMark(
        rect,
        band.color,
        SchedulerBinding.instance.currentFrameTimeStamp,
      ),
    );
    if (_flashes.length > _flashLimit) {
      _flashes.removeRange(0, _flashes.length - _flashLimit);
    }
    _kickFlash();
  }

  Rect? _globalRect(Element element) {
    final render = element.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    return render.localToGlobal(Offset.zero) & render.size;
  }

  RebuildBand _bandFor(_Entry entry) {
    return _thresholds.bandFor(
      buildCount: entry.buildCount,
      buildsPerSecond: entry.rate(_thresholds.rateWindow),
    );
  }

  RebuildWidgetStats _snapshotOf(_Entry entry) {
    final baselineCount = _baseline?.counts.containsKey(entry.id) ?? false
        ? _baseline!.counts[entry.id]
        : null;
    return RebuildWidgetStats(
      id: entry.id,
      name: entry.name,
      location: entry.location,
      source: entry.source,
      buildCount: entry.buildCount,
      initialBuildCount: entry.initialBuildCount,
      parentRebuildCount: entry.parentRebuildCount,
      childRebuildCount: entry.childRebuildCount,
      buildsPerSecond: entry.rate(_thresholds.rateWindow),
      band: _bandFor(entry),
      lastCause: entry.lastCause,
      lastBuildAt: entry.lastBuildAt,
      baselineBuildCount: baselineCount,
      recentBuckets: entry.buckets(),
    );
  }

  void _scheduleEndFrame() {
    if (_endFrameScheduled || _disposed) return;
    _endFrameScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_endFrame);
  }

  void _notifySoon() {
    _changed = true;
    _scheduleEndFrame();
  }

  void _endFrame(Duration _) {
    _endFrameScheduled = false;
    if (_disposed) return;
    for (final monitor in _monitors) {
      monitor.rebuiltThisFrame = false;
    }
    _seenThisFrame.clear();
    final alerts = List<String>.of(_pendingAlerts);
    _pendingAlerts.clear();
    if (alerts.isNotEmpty && onFrequentRebuild != null) {
      final byId = {for (final row in stats) row.id: row};
      for (final id in alerts) {
        final row = byId[id];
        if (row != null) onFrequentRebuild!(row);
      }
    }
    if (_changed) {
      _changed = false;
      notifyListeners();
    }
  }

  void _attachFlashLayer(_RenderFlashLayer layer) {
    _flashLayer = layer;
  }

  void _detachFlashLayer(_RenderFlashLayer layer) {
    if (identical(_flashLayer, layer)) _flashLayer = null;
  }

  void _kickFlash() {
    _flashLayer?.markNeedsPaint();
    if (_flashTicking) return;
    _flashTicking = true;
    _flashTickId = SchedulerBinding.instance.scheduleFrameCallback(
      _onFlashTick,
    );
  }

  void _onFlashTick(Duration timeStamp) {
    _flashTicking = false;
    _flashTickId = null;
    if (_disposed) return;
    _flashes.removeWhere((flash) => flash.progress(timeStamp) <= 0);
    _flashLayer?.markNeedsPaint();
    if (_flashes.isNotEmpty) _kickFlash();
  }

  void _stopFlashTick() {
    final id = _flashTickId;
    if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _flashTickId = null;
    _flashTicking = false;
    _flashes.clear();
  }

  Map<String, Object?> _statsJson(RebuildWidgetStats row) {
    return {
      'name': row.name,
      'location': row.location,
      'source': row.source.name,
      'buildCount': row.buildCount,
      'initialBuildCount': row.initialBuildCount,
      'parentRebuildCount': row.parentRebuildCount,
      'childRebuildCount': row.childRebuildCount,
      'buildsPerSecond': row.buildsPerSecond,
      'band': row.band.name,
      'lastCause': row.lastCause.name,
      'lastBuildAt': row.lastBuildAt?.toIso8601String(),
      'baselineBuildCount': row.baselineBuildCount,
    };
  }

  String _cell(String value) =>
      value.replaceAll('|', '\\|').replaceAll('\n', ' ');

  @override
  void dispose() {
    _disposed = true;
    _forceDetach();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}

class _Entry {
  _Entry({required this.id, required this.name, required this.source});

  final String id;
  String name;
  String? location;
  final RebuildSource source;
  int buildCount = 0;
  int initialBuildCount = 0;
  int parentRebuildCount = 0;
  int childRebuildCount = 0;
  RebuildCause lastCause = RebuildCause.initialBuild;
  RebuildBand notifiedBand = RebuildBand.idle;
  DateTime? lastBuildAt;
  final List<int> timestampsUs = [];

  void touch() {
    final now = DateTime.now();
    lastBuildAt = now;
    timestampsUs.add(now.microsecondsSinceEpoch);
    if (timestampsUs.length > _timestampLimit) {
      timestampsUs.removeAt(0);
    }
  }

  void clearCounts() {
    buildCount = 0;
    initialBuildCount = 0;
    parentRebuildCount = 0;
    childRebuildCount = 0;
    lastCause = RebuildCause.initialBuild;
    notifiedBand = RebuildBand.idle;
    lastBuildAt = null;
    timestampsUs.clear();
  }

  double rate(Duration window) {
    if (timestampsUs.isEmpty) return 0;
    final cutoff =
        DateTime.now().microsecondsSinceEpoch - window.inMicroseconds;
    var count = 0;
    for (var i = timestampsUs.length - 1; i >= 0; i--) {
      if (timestampsUs[i] < cutoff) break;
      count += 1;
    }
    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) return 0;
    return count / seconds;
  }

  List<int> buckets() {
    final result = List<int>.filled(_sparklineBuckets, 0);
    final now = DateTime.now().microsecondsSinceEpoch;
    const width = Duration.microsecondsPerSecond;
    for (final timestamp in timestampsUs) {
      final age = now - timestamp;
      if (age < 0) continue;
      final indexFromEnd = age ~/ width;
      if (indexFromEnd >= _sparklineBuckets) continue;
      result[_sparklineBuckets - 1 - indexFromEnd] += 1;
    }
    return result;
  }
}

class _Baseline {
  const _Baseline({
    required this.label,
    required this.capturedAt,
    required this.counts,
    required this.names,
  });

  final String label;
  final DateTime capturedAt;
  final Map<String, int> counts;
  final Map<String, String> names;
}

class _FlashMark {
  const _FlashMark(this.rect, this.color, this.started);

  final Rect rect;
  final Color color;
  final Duration started;

  double progress(Duration now) {
    final elapsed = now - started;
    if (elapsed <= Duration.zero) return 1;
    if (elapsed >= _flashDuration) return 0;
    return 1 - elapsed.inMicroseconds / _flashDuration.inMicroseconds;
  }
}

class _HookRegistry {
  _HookRegistry() {
    _callback = _dispatch;
  }

  static final _HookRegistry instance = _HookRegistry();

  final Set<RebuildInspectorController> _controllers = {};
  RebuildDirtyWidgetCallback? _previous;
  late final RebuildDirtyWidgetCallback _callback;
  bool _installed = false;

  bool get ownsHook => debugOnRebuildDirtyWidget == _callback;

  void add(RebuildInspectorController controller) {
    _controllers.add(controller);
    _install();
  }

  void remove(RebuildInspectorController controller) {
    _controllers.remove(controller);
    if (_controllers.isEmpty) _uninstall();
  }

  void _install() {
    if (!kDebugMode || _installed) return;
    final current = debugOnRebuildDirtyWidget;
    if (current != null && current != _callback) _previous = current;
    debugOnRebuildDirtyWidget = _callback;
    _installed = true;
  }

  void _uninstall() {
    if (!_installed) return;
    if (debugOnRebuildDirtyWidget == _callback) {
      debugOnRebuildDirtyWidget = _previous;
    }
    _previous = null;
    _installed = false;
  }

  void _dispatch(Element element, bool builtOnce) {
    final current = List<RebuildInspectorController>.of(_controllers);
    for (final controller in current) {
      controller._handleRebuild(element, builtOnce);
    }
    final previous = _previous;
    if (previous != null && previous != _callback) previous(element, builtOnce);
  }
}
