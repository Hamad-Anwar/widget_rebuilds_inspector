part of '../widget_rebuilds_inspector.dart';

/// Counts and highlights rebuilds of [child].
///
/// The count is how often [child]'s element builds:
///
/// * the first mount
/// * a later build because an ancestor rebuilt this slot
/// * a later build because the child called [State.setState], depended on an
///   inherited widget, or was otherwise marked dirty
///
/// An identical child widget is not counted again. That includes a `const`
/// child and a `const` [RebuildInspector]: Flutter skips the subtree, so there
/// was no rebuild to report.
///
/// In release mode this widget returns [child] unchanged unless [enabled] is
/// true. Child-originated builds are visible in debug mode, where Flutter
/// reports them. Parent-driven builds of the slot are counted in every mode.
class RebuildInspector extends StatelessWidget {
  /// Creates an inspector that wraps [child].
  const RebuildInspector({
    super.key,
    required this.name,
    required this.child,
    this.location,
    this.showCounter = true,
    this.highlightRebuilds = true,
    this.highlightColor,
    this.enabled,
    this.controller,
  }) : assert(name != '', 'RebuildInspector.name cannot be empty.');

  /// Name shown in the overlay, badge, and exported report.
  final String name;

  /// Widget whose builds are counted.
  ///
  /// This should be the widget you care about, not a [Builder] that only
  /// exists to host the inspector.
  final Widget child;

  /// Optional location or feature label stored on the report row.
  final String? location;

  /// Paints the current count on top of [child] without affecting layout.
  final bool showCounter;

  /// Flashes a border around [child] when it builds again after mounting.
  ///
  /// The flash only repaints. It does not schedule another widget build, so it
  /// is not included in the count.
  final bool highlightRebuilds;

  /// Border and badge color. When null, the color follows [RebuildBand].
  final Color? highlightColor;

  /// Overrides the nearest [WidgetRebuildInspector.enabled], then [kDebugMode].
  final bool? enabled;

  /// Overrides the nearest [WidgetRebuildInspector] controller.
  final RebuildInspectorController? controller;

  @override
  Widget build(BuildContext context) {
    final scope = _RebuildScope.maybeOf(context);
    final resolvedEnabled = enabled ?? scope?.enabled ?? kDebugMode;
    if (!resolvedEnabled) return child;
    final resolvedController =
        controller ?? scope?.controller ?? RebuildInspectorController.instance;
    return _RebuildMonitor(
      name: name,
      location: location,
      controller: resolvedController,
      showCounter: showCounter,
      highlightRebuilds: highlightRebuilds,
      highlightColor: highlightColor,
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('name', name));
    properties.add(
      FlagProperty('showCounter', value: showCounter, ifTrue: 'shows counter'),
    );
    properties.add(
      FlagProperty(
        'highlightRebuilds',
        value: highlightRebuilds,
        ifTrue: 'highlights rebuilds',
      ),
    );
  }
}

class _RebuildMonitor extends SingleChildRenderObjectWidget {
  const _RebuildMonitor({
    required this.name,
    required this.controller,
    required this.showCounter,
    required this.highlightRebuilds,
    required super.child,
    this.location,
    this.highlightColor,
  });

  final String name;
  final String? location;
  final RebuildInspectorController controller;
  final bool showCounter;
  final bool highlightRebuilds;
  final Color? highlightColor;

  @override
  _RebuildMonitorElement createElement() => _RebuildMonitorElement(this);

  @override
  _RenderRebuildMonitor createRenderObject(BuildContext context) =>
      _RenderRebuildMonitor();

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRebuildMonitor renderObject,
  ) {}
}

class _RebuildMonitorElement extends SingleChildRenderObjectElement {
  _RebuildMonitorElement(super.widget);

  late final String statsId = 'i:${identityHashCode(this)}';

  bool rebuiltThisFrame = false;
  bool hasRecordedBuild = false;

  @override
  _RebuildMonitor get widget => super.widget as _RebuildMonitor;

  RebuildInspectorController get controller => widget.controller;

  Element? get _directChild {
    Element? child;
    visitChildren((element) {
      child ??= element;
    });
    return child;
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    controller._registerMonitor(this);
    rebuiltThisFrame = true;
    controller._scheduleEndFrame();
    super.mount(parent, newSlot);
    // Render-object children do not go through Element.rebuild, so the debug
    // hook never sees them. Component children are counted from that hook.
    final child = _directChild;
    if (child is! ComponentElement &&
        controller.enabled &&
        !controller.paused) {
      controller._recordBoundary(this);
    }
    syncVisuals(flash: false);
  }

  @override
  void update(covariant _RebuildMonitor newWidget) {
    final previousController = widget.controller;
    if (!identical(previousController, newWidget.controller)) {
      previousController._unregisterMonitor(this);
      newWidget.controller._registerMonitor(this);
    }
    rebuiltThisFrame = true;
    newWidget.controller._scheduleEndFrame();
    Element? previousChild;
    visitChildren((element) => previousChild ??= element);
    final previousChildWidget = previousChild?.widget;
    super.update(newWidget);
    final child = _directChild;
    final childWidgetChanged =
        child != null && !identical(previousChildWidget, child.widget);
    if (childWidgetChanged &&
        child is! ComponentElement &&
        controller.enabled &&
        !controller.paused) {
      final flash = hasRecordedBuild && widget.highlightRebuilds;
      controller._recordBoundary(this);
      syncVisuals(flash: flash);
      return;
    }
    syncVisuals(flash: false);
  }

  @override
  void unmount() {
    final render = renderObject;
    if (render is _RenderRebuildMonitor) render.stopTicking();
    controller._unregisterMonitor(this);
    super.unmount();
  }

  void syncVisuals({required bool flash}) {
    final render = renderObject;
    if (render is! _RenderRebuildMonitor) return;
    final stats = controller.statsFor(statsId);
    final band = stats?.band ?? RebuildBand.idle;
    render.sync(
      buildCount: stats?.buildCount ?? 0,
      showCounter: widget.showCounter,
      color: widget.highlightColor ?? band.color,
      flash: flash,
    );
  }
}

class _RenderRebuildMonitor extends RenderProxyBox {
  int _buildCount = 0;
  bool _showCounter = false;
  Color _color = RebuildBand.idle.color;
  Duration? _flashStart;
  int? _tickId;
  TextPainter? _badgePainter;
  int _badgeCount = -1;

  void sync({
    required int buildCount,
    required bool showCounter,
    required Color color,
    required bool flash,
  }) {
    final visualChanged =
        _buildCount != buildCount ||
        _showCounter != showCounter ||
        _color != color;
    _buildCount = buildCount;
    _showCounter = showCounter;
    _color = color;
    if (flash) {
      _flashStart = SchedulerBinding.instance.currentFrameTimeStamp;
      _ensureTick();
    }
    if ((visualChanged || flash) && attached) markNeedsPaint();
  }

  void stopTicking() {
    final id = _tickId;
    if (id != null) SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _tickId = null;
  }

  void _ensureTick() {
    if (_tickId != null) return;
    _tickId = SchedulerBinding.instance.scheduleFrameCallback(_onTick);
  }

  void _onTick(Duration timeStamp) {
    _tickId = null;
    if (!attached) return;
    markNeedsPaint();
    if (_progress(timeStamp) > 0) _ensureTick();
  }

  double _progress(Duration now) {
    final start = _flashStart;
    if (start == null) return 0;
    final elapsed = now - start;
    if (elapsed <= Duration.zero) return 1;
    if (elapsed >= _flashDuration) return 0;
    return 1 - elapsed.inMicroseconds / _flashDuration.inMicroseconds;
  }

  @override
  void detach() {
    stopTicking();
    super.detach();
  }

  @override
  void dispose() {
    stopTicking();
    _badgePainter?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final progress = _progress(now);
    final bounds = offset & size;
    final canvas = context.canvas;
    if (progress > 0 && !size.isEmpty) {
      final rect = bounds.deflate(1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.fill
          ..color = _color.withValues(alpha: 0.14 * progress),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = _color.withValues(alpha: 0.2 + 0.8 * progress),
      );
    }
    if (_showCounter && _buildCount > 0 && !size.isEmpty) {
      _paintBadge(canvas, bounds);
    }
  }

  void _paintBadge(Canvas canvas, Rect bounds) {
    final label = _buildCount > 999 ? '999+' : '$_buildCount';
    if (_badgePainter == null || _badgeCount != _buildCount) {
      _badgePainter?.dispose();
      _badgePainter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _badgeCount = _buildCount;
    }
    final painter = _badgePainter!;
    const padX = 5.0;
    const padY = 3.0;
    final width = painter.width + padX * 2;
    final height = painter.height + padY * 2;
    final rect = Rect.fromLTWH(
      bounds.right - width - 2,
      bounds.top + 2,
      width,
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = _color,
    );
    painter.paint(canvas, Offset(rect.left + padX, rect.top + padY));
  }
}
