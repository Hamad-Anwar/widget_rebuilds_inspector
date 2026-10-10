import 'package:flutter_test/flutter_test.dart';
import 'package:widget_rebuilds_inspector_example/main.dart';

void main() {
  testWidgets('demo shows the inbox and the inspector', (tester) async {
    await tester.pumpWidget(const RebuildDemoApp());
    await tester.pump();

    expect(find.text('Simulate parent rebuild'), findsOneWidget);
    expect(find.text('Widget Rebuild Inspector'), findsOneWidget);
    expect(find.text('ProfileHeader'), findsWidgets);

    await tester.tap(find.text('Close'));
    await tester.pump();

    await tester.tap(find.text('Simulate parent rebuild'));
    await tester.pump();
    expect(find.textContaining('Parent revision 1'), findsOneWidget);

    await tester.tap(find.text('Add notification'));
    await tester.pump();
    expect(find.textContaining('4 unread'), findsOneWidget);
  });
}
