import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widget_rebuilds_inspector/src/resource_usage.dart';
import 'package:widget_rebuilds_inspector/widget_rebuilds_inspector.dart';

void main() {
  tearDown(RebuildInspectorController.debugResetInstance);

  test('bands follow the higher of count and rate', () {
    const thresholds = RebuildThresholds();
    expect(
      thresholds.bandFor(buildCount: 2, buildsPerSecond: 0),
      RebuildBand.low,
    );
    expect(
      thresholds.bandFor(buildCount: 3, buildsPerSecond: 0),
      RebuildBand.low,
    );
    expect(
      thresholds.bandFor(buildCount: 31, buildsPerSecond: 0),
      RebuildBand.moderate,
    );
    expect(
      thresholds.bandFor(buildCount: 47, buildsPerSecond: 0),
      RebuildBand.frequent,
    );
    expect(
      thresholds.bandFor(buildCount: 12, buildsPerSecond: 10),
      RebuildBand.frequent,
    );
  });

  testWidgets('parent rebuilds count every non-const slot once', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(_host(_ParentHarness(controller: controller)));
    await tester.pump();

    expect(stat(controller, 'ProfileHeader').buildCount, 1);
    expect(stat(controller, 'NotificationCounter').buildCount, 1);
    expect(stat(controller, 'Frozen').buildCount, 1);
    expect(stat(controller, 'ProfileHeader').initialBuildCount, 1);

    await tester.tap(find.text('parent 0'));
    await tester.pump();

    expect(stat(controller, 'ProfileHeader').buildCount, 2);
    expect(stat(controller, 'ProfileHeader').parentRebuildCount, 1);
    expect(stat(controller, 'ProfileHeader').childRebuildCount, 0);
    expect(stat(controller, 'NotificationCounter').parentRebuildCount, 1);
    expect(stat(controller, 'Frozen').buildCount, 1);
    expect(stat(controller, 'Box').buildCount, 2);

    await tester.pump(const Duration(milliseconds: 700));
    expect(stat(controller, 'ProfileHeader').buildCount, 2);
  });

  testWidgets('a const inspector is skipped when the parent rebuilds', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(_host(_ConstHarness(controller: controller)));
    await tester.pump();
    expect(stat(controller, 'ConstHeader').buildCount, 1);

    await tester.tap(find.text('rebuild'));
    await tester.pump();
    expect(stat(controller, 'ConstHeader').buildCount, 1);
  });

  testWidgets('setState inside the child does not rebuild siblings', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(_host(_ParentHarness(controller: controller)));
    await tester.pump();

    await tester.tap(find.text('notes 0'));
    await tester.pump();

    expect(stat(controller, 'NotificationCounter').buildCount, 2);
    expect(stat(controller, 'NotificationCounter').childRebuildCount, 1);
    expect(stat(controller, 'NotificationCounter').parentRebuildCount, 0);
    expect(stat(controller, 'ProfileHeader').buildCount, 1);
    expect(find.text('notes 1'), findsOneWidget);
  });

  testWidgets('disabled inspector does not record or wrap', (tester) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(
      _host(_ParentHarness(controller: controller, enabled: false)),
    );
    await tester.pump();
    expect(controller.stats, isEmpty);

    await tester.tap(find.text('parent 0'));
    await tester.pump();
    expect(controller.stats, isEmpty);
    expect(find.text('profile 1'), findsOneWidget);
  });

  testWidgets('baseline, reset, and export describe the session', (
    tester,
  ) async {
    final controller = RebuildInspectorController(
      thresholds: const RebuildThresholds(
        moderatePerSecond: 1000,
        frequentPerSecond: 2000,
      ),
    );
    await tester.pumpWidget(_host(_ParentHarness(controller: controller)));
    await tester.pump();
    controller.markBaseline('before');

    await tester.tap(find.text('parent 0'));
    await tester.pump();

    final comparison = controller.compareToBaseline();
    final header = comparison!.deltas.firstWhere(
      (delta) => delta.name == 'ProfileHeader',
    );
    expect(header.before, 1);
    expect(header.after, 2);
    expect(header.change, 1);
    expect(stat(controller, 'ProfileHeader').band, RebuildBand.low);

    final markdown = controller.exportMarkdown();
    expect(markdown, contains('ProfileHeader'));
    expect(markdown, contains(rebuildInspectorDisclaimer));
    expect(controller.exportJson(), contains('"buildCount": 2'));

    controller.reset();
    expect(stat(controller, 'ProfileHeader').buildCount, 0);
    expect(controller.hasBaseline, isTrue);

    controller.clearBaseline();
    expect(controller.hasBaseline, isFalse);
  });

  testWidgets('count thresholds mark a busy widget frequent', (tester) async {
    final hits = <String>[];
    final controller = RebuildInspectorController();
    const thresholds = RebuildThresholds(
      moderateAfter: 1,
      frequentAfter: 2,
      moderatePerSecond: 1000,
      frequentPerSecond: 2000,
    );
    await tester.pumpWidget(
      _host(
        _ParentHarness(
          controller: controller,
          thresholds: thresholds,
          onFrequentRebuild: (row) => hits.add(row.name),
        ),
      ),
    );
    await tester.pump();
    expect(hits, isEmpty);

    await tester.tap(find.text('parent 0'));
    await tester.pump();
    expect(stat(controller, 'ProfileHeader').band, RebuildBand.frequent);
    expect(hits, ['ProfileHeader', 'NotificationCounter', 'Box']);
  });

  testWidgets('automatic mode records a user widget after it rebuilds', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(
      _host(
        WidgetRebuildInspector(
          controller: controller,
          showOverlay: false,
          automaticTracking: true,
          userWidgetsOnly: false,
          child: const SignalLight(),
        ),
      ),
    );
    await tester.pump();
    expect(controller.stats.where((row) => row.name == 'SignalLight'), isEmpty);

    await tester.tap(find.text('signal 0'));
    await tester.pump();
    expect(stat(controller, 'SignalLight').buildCount, 1);
    expect(stat(controller, 'SignalLight').source, RebuildSource.automatic);
    expect(controller.stats.where((row) => row.name == 'Text'), isEmpty);
  });

  testWidgets('overlay lists instrumented widgets and can collapse', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(
      _host(_ParentHarness(controller: controller, overlay: true)),
    );
    await tester.pump();

    expect(find.text('Widget Rebuild Inspector'), findsOneWidget);
    expect(find.text('ProfileHeader'), findsOneWidget);
    expect(find.text('1×'), findsWidgets);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(find.text('Widget Rebuild Inspector'), findsNothing);
    expect(
      find.byKey(const Key('widget-rebuilds-inspector-chip')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('widget-rebuilds-inspector-chip')));
    await tester.pump();
    expect(find.text('Widget Rebuild Inspector'), findsOneWidget);
  });

  testWidgets('automatic mode ignores the inspector and toggles update', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(
      _host(_ParentHarness(controller: controller, overlay: true)),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('widget-rebuilds-inspector-automatic')),
    );
    await tester.pump();
    expect(controller.automaticTracking, isTrue);
    expect(find.text('On'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('widget-rebuilds-inspector-hotspots')),
    );
    await tester.pump();
    expect(controller.highlightHotspots, isTrue);
    expect(find.text('On'), findsNWidgets(2));

    final before = controller.stats.fold<int>(
      0,
      (sum, row) => sum + row.buildCount,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      controller.stats.where((row) => row.name == '_RebuildOverlay'),
      isEmpty,
    );
    expect(
      controller.stats.where((row) => row.name == '_CollapsedChip'),
      isEmpty,
    );
    final after = controller.stats.fold<int>(
      0,
      (sum, row) => sum + row.buildCount,
    );
    expect(after, before);

    await tester.tap(
      find.byKey(const Key('widget-rebuilds-inspector-automatic')),
    );
    await tester.pump();
    expect(controller.automaticTracking, isFalse);
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('overlay shows live memory and storage', (tester) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(
      _host(_ParentHarness(controller: controller, overlay: true)),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('widget-rebuilds-inspector-resources')),
      findsOneWidget,
    );
    expect(find.textContaining('RAM'), findsOneWidget);
    expect(find.textContaining('Storage'), findsOneWidget);
    expect(find.textContaining('MB'), findsWidgets);
  });

  test('process memory is readable', () async {
    final sample = await readResourceUsage();
    expect(sample.ramBytes, greaterThan(0));
    expect(sample.measuredStorage, isTrue);
  });

  testWidgets('unmounting the inspector releases the debug hook', (
    tester,
  ) async {
    final controller = RebuildInspectorController();
    await tester.pumpWidget(_host(_ParentHarness(controller: controller)));
    await tester.pump();
    expect(controller.hookConnected, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(debugOnRebuildDirtyWidget, isNull);
  });
}

RebuildWidgetStats stat(RebuildInspectorController controller, String name) {
  return controller.stats.firstWhere((row) => row.name == name);
}

Widget _host(Widget child) {
  return Directionality(textDirection: TextDirection.ltr, child: child);
}

class _ParentHarness extends StatefulWidget {
  const _ParentHarness({
    required this.controller,
    this.enabled = true,
    this.overlay = false,
    this.thresholds = const RebuildThresholds(),
    this.onFrequentRebuild,
  });

  final RebuildInspectorController controller;
  final bool enabled;
  final bool overlay;
  final RebuildThresholds thresholds;
  final void Function(RebuildWidgetStats stats)? onFrequentRebuild;

  @override
  State<_ParentHarness> createState() => _ParentHarnessState();
}

class _ParentHarnessState extends State<_ParentHarness> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    return WidgetRebuildInspector(
      controller: widget.controller,
      enabled: widget.enabled,
      showOverlay: widget.overlay,
      initiallyExpanded: widget.overlay,
      thresholds: widget.thresholds,
      onFrequentRebuild: widget.onFrequentRebuild,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => revision++),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('parent $revision'),
            ),
          ),
          RebuildInspector(
            name: 'ProfileHeader',
            child: Text('profile $revision'),
          ),
          RebuildInspector(
            name: 'NotificationCounter',
            child: _Notes(revision: revision),
          ),
          RebuildInspector(
            name: 'Box',
            child: SizedBox(
              width: 12 + revision.toDouble(),
              height: 12,
              child: const Text('box'),
            ),
          ),
          const RebuildInspector(name: 'Frozen', child: Text('frozen')),
        ],
      ),
    );
  }
}

class _Notes extends StatefulWidget {
  const _Notes({required this.revision});

  final int revision;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  int notes = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => notes++),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('notes $notes'),
      ),
    );
  }
}

class _ConstHarness extends StatefulWidget {
  const _ConstHarness({required this.controller});

  final RebuildInspectorController controller;

  @override
  State<_ConstHarness> createState() => _ConstHarnessState();
}

class _ConstHarnessState extends State<_ConstHarness> {
  int revision = 0;

  @override
  Widget build(BuildContext context) {
    return WidgetRebuildInspector(
      controller: widget.controller,
      showOverlay: false,
      child: Column(
        children: [
          GestureDetector(
            onTap: () => setState(() => revision++),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('rebuild'),
            ),
          ),
          Text('$revision', key: const ValueKey('revision')),
          const RebuildInspector(name: 'ConstHeader', child: Text('still')),
        ],
      ),
    );
  }
}

class SignalLight extends StatefulWidget {
  const SignalLight({super.key});

  @override
  State<SignalLight> createState() => _SignalLightState();
}

class _SignalLightState extends State<SignalLight> {
  int n = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => n++),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('signal $n'),
      ),
    );
  }
}
