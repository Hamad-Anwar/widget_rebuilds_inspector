part of '../widget_rebuilds_inspector.dart';

const Color _panel = Color(0xFFFFFFFF);
const Color _panelBorder = Color(0xFFE2E8F0);
const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF475569);
const Color _soft = Color(0xFFF8FAFC);
const Color _trackOff = Color(0xFFCBD5E1);
const Color _accent = Color(0xFF1D4ED8);
const Color _onAccent = Color(0xFFFFFFFF);
const Color _knob = Color(0xFFFFFFFF);

const TextStyle _overlayText = TextStyle(
  inherit: false,
  color: _ink,
  fontSize: 13,
  height: 1.3,
  decoration: TextDecoration.none,
);

const TextStyle _metricValue = TextStyle(
  inherit: false,
  color: _ink,
  fontFamily: 'monospace',
  fontSize: 18,
  fontWeight: FontWeight.w600,
  height: 1.2,
  decoration: TextDecoration.none,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Floating debug panel. Rebuilds are scoped to this widget, not the app child.
class _RebuildOverlay extends StatefulWidget {
  const _RebuildOverlay({
    required this.controller,
    required this.initiallyExpanded,
  });

  final RebuildInspectorController controller;
  final bool initiallyExpanded;

  @override
  State<_RebuildOverlay> createState() => _RebuildOverlayState();
}

class _RebuildOverlayState extends State<_RebuildOverlay> {
  final GlobalKey _panelKey = GlobalKey(
    debugLabel: 'widget_rebuilds_inspector.panel',
  );
  late bool _expanded;
  Timer? _resourceTimer;
  bool _samplingStorage = false;
  int _resourceTicks = 0;
  int? _ramBytes;
  int? _storageBytes;

  RebuildInspectorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    controller.addListener(_onController);
    if (resourceUsageSupported) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _sampleResources());
      _resourceTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _sampleResources();
      });
    }
  }

  @override
  void didUpdateWidget(_RebuildOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _resourceTimer?.cancel();
    controller.removeListener(_onController);
    super.dispose();
  }

  void _sampleResources() {
    if (!mounted) return;
    final ram = readProcessRamBytes();
    setState(() => _ramBytes = ram);
    _resourceTicks += 1;
    if (_samplingStorage) return;
    if (_storageBytes != null && _resourceTicks % 3 != 1) return;
    _samplingStorage = true;
    readAppStorageBytes()
        .then((storage) {
          _samplingStorage = false;
          if (!mounted) return;
          setState(() => _storageBytes = storage);
        })
        .catchError((Object _) {
          _samplingStorage = false;
        });
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  void _setAutomatic(bool value) {
    controller.automaticTracking = value;
    setState(() {});
  }

  void _setHotspots(bool value) {
    controller.highlightHotspots = value;
    setState(() {});
  }

  void _setPaused(bool value) {
    controller.paused = value;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final view = View.of(context);
    final screen = media?.size ?? view.physicalSize / view.devicePixelRatio;
    final bottomInset = media?.padding.bottom ?? 0;
    final width = math.min(380.0, screen.width - 24);
    final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final panel = Directionality(
      textDirection: direction,
      child: DefaultTextStyle(
        style: _overlayText,
        child: _InspectorChrome(
          child: _expanded
              ? _buildPanel(width, screen)
              : _CollapsedChip(
                  controller: controller,
                  onOpen: () => setState(() => _expanded = true),
                ),
        ),
      ),
    );

    return Positioned(
      right: 16,
      bottom: bottomInset + 16,
      width: _expanded ? width : null,
      child: panel,
    );
  }

  Widget _buildPanel(double width, Size screen) {
    final stats = controller.stats;
    final instrumented = [
      for (final row in stats)
        if (row.source == RebuildSource.instrumented) row,
    ];
    final detected = [
      for (final row in stats)
        if (row.source == RebuildSource.automatic) row,
    ];
    final cap = math.max(160.0, screen.height - 360);
    final rowBudget = math.max(stats.length, 1) * 56.0 + 32;
    final listHeight = math.min(rowBudget, cap);

    return SizedBox(
      key: _panelKey,
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _panelBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x330F172A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x240F172A),
              blurRadius: 42,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: _panel,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  if (resourceUsageSupported) ...[
                    const SizedBox(height: 12),
                    _resources(),
                  ],
                  const SizedBox(height: 12),
                  _controls(),
                  if (_warning() case final warning?) ...[
                    const SizedBox(height: 8),
                    warning,
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: listHeight,
                    child: _rows(instrumented, detected),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Widget Rebuild Inspector',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _ActionButton(
          label: 'Close',
          mark: _Mark.close,
          onPressed: () => setState(() => _expanded = false),
        ),
      ],
    );
  }

  Widget _resources() {
    return DecoratedBox(
      key: const Key('widget-rebuilds-inspector-resources'),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: _MetricReadout(
                label: 'RAM',
                value: _formatBytes(_ramBytes),
                caption: 'This process',
              ),
            ),
            const ColoredBox(
              color: _panelBorder,
              child: SizedBox(width: 1, height: 44),
            ),
            Expanded(
              child: _MetricReadout(
                label: 'Storage',
                value: _formatBytes(_storageBytes),
                caption: 'Saved files',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Column(
      children: [
        _SwitchRow(
          controlKey: const Key('widget-rebuilds-inspector-automatic'),
          label: 'Automatic',
          hint: 'Count widgets you did not wrap',
          value: controller.automaticTracking,
          onChanged: _setAutomatic,
        ),
        const ColoredBox(color: _panelBorder, child: SizedBox(height: 1)),
        _SwitchRow(
          controlKey: const Key('widget-rebuilds-inspector-hotspots'),
          label: 'Hotspots',
          hint: 'Outline widgets that rebuild a lot',
          value: controller.highlightHotspots,
          onChanged: _setHotspots,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ActionButton(
                label: controller.paused ? 'Paused' : 'Pause',
                mark: controller.paused ? _Mark.play : _Mark.pause,
                filled: controller.paused,
                expand: true,
                onPressed: () => _setPaused(!controller.paused),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionButton(
                label: 'Reset',
                mark: _Mark.reset,
                expand: true,
                onPressed: controller.reset,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget? _warning() {
    if (!controller.automaticTracking || controller.hookConnected) return null;
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0xFFFFFBEB),
        borderRadius: BorderRadius.all(Radius.circular(8)),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFFFCD34D))),
      ),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Automatic is paused because another tool owns the rebuild hook.',
          style: TextStyle(
            color: Color(0xFF92400E),
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _rows(
    List<RebuildWidgetStats> instrumented,
    List<RebuildWidgetStats> detected,
  ) {
    if (instrumented.isEmpty && detected.isEmpty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: Text(
          'Wrap a widget with RebuildInspector, or turn Automatic on.',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (instrumented.isNotEmpty) ...[
          _section('Wrapped'),
          for (final row in instrumented) _row(row),
        ],
        if (detected.isNotEmpty) ...[
          _section('Other'),
          for (final row in detected) _row(row),
        ],
      ],
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: _muted,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _row(RebuildWidgetStats row) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _panelBorder)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: row.band.color,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detail(row),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${row.buildCount}×',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '—';
    const kb = 1024;
    const mb = 1024 * 1024;
    const gb = 1024 * 1024 * 1024;
    if (bytes < kb) return '$bytes B';
    if (bytes < mb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    if (bytes < gb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / gb).toStringAsFixed(2)} GB';
  }

  String _detail(RebuildWidgetStats row) {
    final parts = <String>[
      if (row.parentRebuildCount > 0) '${row.parentRebuildCount} from parent',
      if (row.childRebuildCount > 0) '${row.childRebuildCount} from itself',
      if (row.buildsPerSecond >= 0.1)
        '${row.buildsPerSecond.toStringAsFixed(1)}/s',
    ];
    if (parts.isEmpty) return row.band.label;
    return '${parts.join(' · ')} · ${row.band.label}';
  }
}

class _CollapsedChip extends StatelessWidget {
  const _CollapsedChip({required this.controller, required this.onOpen});

  final RebuildInspectorController controller;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    var hottest = 0;
    var frequent = false;
    for (final row in stats) {
      if (row.buildCount > hottest) hottest = row.buildCount;
      if (row.band == RebuildBand.frequent) frequent = true;
    }
    final label = hottest > 0 ? 'Rebuilds · $hottest×' : 'Rebuilds';
    return Semantics(
      button: true,
      child: _Pressable(
        key: const Key('widget-rebuilds-inspector-chip'),
        onPressed: onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: frequent ? RebuildBand.frequent.color : _panelBorder,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 2,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x2E0F172A),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: frequent ? RebuildBand.frequent.color : _accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      inherit: false,
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.controlKey,
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  final Key controlKey;
  final String label;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: value,
      label: '$label. $hint. ${value ? 'On' : 'Off'}',
      child: _Pressable(
        key: controlKey,
        minHeight: 44,
        onPressed: () => onChanged(!value),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value ? 'On' : 'Off',
              style: TextStyle(
                color: value ? _accent : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            _SwitchTrack(on: value),
          ],
        ),
      ),
    );
  }
}

class _MetricReadout extends StatelessWidget {
  const _MetricReadout({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: _metricValue),
          Text(caption, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.mark,
    required this.onPressed,
    this.filled = false,
    this.expand = false,
  });

  final String label;
  final _Mark mark;
  final VoidCallback onPressed;
  final bool filled;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? _onAccent : _ink;
    return Semantics(
      button: true,
      child: _Pressable(
        onPressed: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: filled ? _accent : _soft,
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: _panelBorder),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MarkIcon(mark, color: foreground),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    super.key,
    required this.onPressed,
    required this.child,
    this.minHeight = 44,
  });

  final VoidCallback onPressed;
  final Widget child;
  final double minHeight;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onPressed,
      child: Opacity(
        opacity: _pressed ? 0.72 : 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          child: widget.child,
        ),
      ),
    );
  }
}

class _SwitchTrack extends StatelessWidget {
  const _SwitchTrack({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 40,
        height: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: on ? _accent : _trackOff,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Align(
              alignment: on ? Alignment.centerRight : Alignment.centerLeft,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: _knob,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x330F172A),
                      blurRadius: 2,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                child: SizedBox.square(dimension: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Mark { close, pause, play, reset }

class _MarkIcon extends StatelessWidget {
  const _MarkIcon(this.mark, {required this.color});

  final _Mark mark;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 16,
        height: 16,
        child: CustomPaint(painter: _MarkPainter(mark, color)),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.mark, this.color);

  final _Mark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (mark) {
      case _Mark.close:
        canvas.drawLine(
          const Offset(3, 3),
          Offset(size.width - 3, size.height - 3),
          stroke,
        );
        canvas.drawLine(
          Offset(size.width - 3, 3),
          Offset(3, size.height - 3),
          stroke,
        );
      case _Mark.pause:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 2, 3.2, 12),
            const Radius.circular(1),
          ),
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(9.8, 2, 3.2, 12),
            const Radius.circular(1),
          ),
          fill,
        );
      case _Mark.play:
        final path = Path()
          ..moveTo(4, 2)
          ..lineTo(13, 8)
          ..lineTo(4, 14)
          ..close();
        canvas.drawPath(path, fill);
      case _Mark.reset:
        canvas.drawArc(
          Rect.fromLTWH(2.5, 2.5, size.width - 5, size.height - 5),
          -0.5,
          4.6,
          false,
          stroke,
        );
        canvas.drawLine(
          Offset(size.width - 3.2, 3.2),
          Offset(size.width - 3.2, 7),
          stroke,
        );
        canvas.drawLine(
          Offset(size.width - 7, 3.2),
          Offset(size.width - 3.2, 3.2),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) {
    return oldDelegate.mark != mark || oldDelegate.color != color;
  }
}
