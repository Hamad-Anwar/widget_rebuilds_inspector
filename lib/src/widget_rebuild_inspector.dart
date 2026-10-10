part of '../widget_rebuilds_inspector.dart';

/// Provides a [RebuildInspectorController] to descendant [RebuildInspector]s.
class _RebuildScope extends InheritedWidget {
  const _RebuildScope({
    required this.controller,
    required this.enabled,
    required super.child,
  });

  final RebuildInspectorController controller;
  final bool enabled;

  static _RebuildScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_RebuildScope>();
  }

  @override
  bool updateShouldNotify(_RebuildScope oldWidget) {
    return oldWidget.controller != controller || oldWidget.enabled != enabled;
  }
}

/// Marks overlay widgets so automatic detection does not record the inspector UI.
class _InspectorChrome extends InheritedWidget {
  const _InspectorChrome({required super.child});

  @override
  bool updateShouldNotify(_InspectorChrome oldWidget) => false;
}

/// In-app host for the rebuild overlay and automatic detection.
///
/// Place this above the tree you want to inspect, usually in [WidgetsApp.builder]
/// or [MaterialApp.builder]. Descendants can use [RebuildInspector] without
/// passing a controller.
///
/// [enabled] defaults to [kDebugMode]. In release builds the [child] is
/// returned directly and the debug hook is not installed.
class WidgetRebuildInspector extends StatefulWidget {
  /// Creates an inspector around [child].
  const WidgetRebuildInspector({
    super.key,
    required this.child,
    this.controller,
    this.enabled = kDebugMode,
    this.showOverlay = true,
    this.initiallyExpanded = false,
    this.automaticTracking = false,
    this.userWidgetsOnly = true,
    this.ignoreCommonWidgets = true,
    this.highlightHotspots = false,
    this.thresholds = const RebuildThresholds(),
    this.onFrequentRebuild,
  });

  /// The app or subtree to inspect.
  final Widget child;

  /// Store for counts. When null, a controller is created and owned here.
  ///
  /// Settings on this widget are copied onto [controller] when they change,
  /// including the first build. Overlay switches then own those values until
  /// the corresponding setting on this widget changes.
  final RebuildInspectorController? controller;

  /// When false, [child] is shown without a monitor, overlay, or debug hook.
  final bool enabled;

  /// Whether to paint the draggable debug panel.
  final bool showOverlay;

  /// Whether the panel starts open.
  final bool initiallyExpanded;

  /// Whether to record user widgets that are not wrapped in [RebuildInspector].
  final bool automaticTracking;

  /// When true, automatic mode keeps widgets created in the app target.
  final bool userWidgetsOnly;

  /// When true, automatic mode hides common layout and Material widgets.
  final bool ignoreCommonWidgets;

  /// When true, detected widgets in [RebuildBand.frequent] flash on screen.
  final bool highlightHotspots;

  /// Cutoffs for [RebuildBand].
  final RebuildThresholds thresholds;

  /// Called after a row first becomes [RebuildBand.frequent].
  final void Function(RebuildWidgetStats stats)? onFrequentRebuild;

  @override
  State<WidgetRebuildInspector> createState() => _WidgetRebuildInspectorState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(FlagProperty('enabled', value: enabled, ifTrue: 'enabled'));
    properties.add(
      FlagProperty(
        'automaticTracking',
        value: automaticTracking,
        ifTrue: 'automatic',
      ),
    );
  }
}

class _WidgetRebuildInspectorState extends State<WidgetRebuildInspector> {
  late RebuildInspectorController _controller;
  bool _ownsController = false;
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    _bind(widget, null);
  }

  @override
  void didUpdateWidget(WidgetRebuildInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind(widget, oldWidget);
  }

  void _bind(WidgetRebuildInspector next, WidgetRebuildInspector? previous) {
    if (previous == null || !identical(previous.controller, next.controller)) {
      _setAttached(false);
      if (_ownsController) {
        _controller.dispose();
        _ownsController = false;
      }
      if (next.controller != null) {
        _controller = next.controller!;
      } else {
        _controller = RebuildInspectorController();
        _ownsController = true;
      }
    }
    _apply(next, previous);
    _setAttached(next.enabled);
  }

  void _apply(WidgetRebuildInspector next, WidgetRebuildInspector? previous) {
    void apply<T>(T? oldValue, T newValue, void Function(T value) assign) {
      if (previous == null || oldValue != newValue) assign(newValue);
    }

    apply(
      previous?.automaticTracking,
      next.automaticTracking,
      (value) => _controller.automaticTracking = value,
    );
    apply(
      previous?.userWidgetsOnly,
      next.userWidgetsOnly,
      (value) => _controller.userWidgetsOnly = value,
    );
    apply(
      previous?.ignoreCommonWidgets,
      next.ignoreCommonWidgets,
      (value) => _controller.ignoreCommonWidgets = value,
    );
    apply(
      previous?.highlightHotspots,
      next.highlightHotspots,
      (value) => _controller.highlightHotspots = value,
    );
    apply(
      previous?.thresholds,
      next.thresholds,
      (value) => _controller.thresholds = value,
    );
    apply(
      previous?.onFrequentRebuild,
      next.onFrequentRebuild,
      (value) => _controller.onFrequentRebuild = value,
    );
    _controller.enabled = next.enabled;
  }

  void _setAttached(bool active) {
    if (active == _attached) return;
    if (active) {
      _controller._attach();
    } else {
      _controller._detach();
    }
    _attached = active;
  }

  @override
  void dispose() {
    _setAttached(false);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _RebuildScope(
      controller: _controller,
      enabled: widget.enabled,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (widget.enabled) const _FlashBarrier(),
          if (widget.enabled && widget.showOverlay)
            _RebuildOverlay(
              controller: _controller,
              initiallyExpanded: widget.initiallyExpanded,
            ),
        ],
      ),
    );
  }
}

class _FlashBarrier extends StatelessWidget {
  const _FlashBarrier();

  @override
  Widget build(BuildContext context) {
    final scope = _RebuildScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(child: _FlashLayer(scope.controller)),
    );
  }
}

class _FlashLayer extends LeafRenderObjectWidget {
  const _FlashLayer(this.controller);

  final RebuildInspectorController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFlashLayer(controller);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFlashLayer renderObject,
  ) {
    renderObject.controller = controller;
  }
}

class _RenderFlashLayer extends RenderBox {
  _RenderFlashLayer(this._controller);

  RebuildInspectorController _controller;

  RebuildInspectorController get controller => _controller;

  set controller(RebuildInspectorController value) {
    if (identical(_controller, value)) return;
    if (attached) _controller._detachFlashLayer(this);
    _controller = value;
    if (attached) _controller._attachFlashLayer(this);
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller._attachFlashLayer(this);
    if (_controller._flashes.isNotEmpty) _controller._kickFlash();
  }

  @override
  void detach() {
    _controller._detachFlashLayer(this);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    final flashes = _controller._flashes;
    if (flashes.isEmpty) return;
    final origin = localToGlobal(Offset.zero);
    final now = SchedulerBinding.instance.currentFrameTimeStamp;
    final canvas = context.canvas;
    for (final flash in flashes) {
      final progress = flash.progress(now);
      if (progress <= 0) continue;
      final rect = flash.rect.shift(-origin).shift(offset);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(6)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = flash.color.withValues(alpha: 0.25 + 0.75 * progress),
      );
    }
  }
}
