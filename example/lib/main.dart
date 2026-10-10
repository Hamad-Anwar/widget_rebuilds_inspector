import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:widget_rebuilds_inspector/widget_rebuilds_inspector.dart';

void main() {
  runApp(const RebuildDemoApp());
}

/// Sample inbox that makes parent rebuilds and local `setState` visible.
class RebuildDemoApp extends StatelessWidget {
  /// Creates the demo app.
  const RebuildDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Widget Rebuild Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E6B4F)),
        scaffoldBackgroundColor: const Color(0xFFF6F4EF),
      ),
      builder: (context, child) {
        return WidgetRebuildInspector(
          enabled: kDebugMode,
          initiallyExpanded: true,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const InboxPage(),
    );
  }
}

/// Inbox whose sections are each wrapped in [RebuildInspector].
class InboxPage extends StatefulWidget {
  /// Creates the inbox page.
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  int _revision = 0;

  void _rebuildParent() => setState(() => _revision++);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: const Color(0xFFF6F4EF),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            'Parent revision $_revision',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'A parent rebuild refreshes every section that is not const. '
            'A local setState should refresh only that section. The overlay counts what actually built.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _rebuildParent,
            child: const Text('Simulate parent rebuild'),
          ),
          const SizedBox(height: 20),
          _Card(title: 'ProfileHeader', body: 'Ava Chen · revision $_revision'),
          const SizedBox(height: 12),
          RebuildInspector(
            name: 'UserInformation',
            child: _Card(
              title: 'UserInformation',
              body: 'Product design · revision $_revision',
            ),
          ),
          const SizedBox(height: 12),
          RebuildInspector(
            name: 'NotificationCounter',
            child: NotificationCounter(revision: _revision),
          ),
          const SizedBox(height: 12),
          const RebuildInspector(
            name: 'RecentActivity',
            child: RecentActivity(),
          ),
        ],
      ),
    );
  }
}

/// Notification count that can rebuild without the inbox rebuilding.
class NotificationCounter extends StatefulWidget {
  /// Creates a counter tied to the latest parent [revision].
  const NotificationCounter({super.key, required this.revision});

  /// Value from the parent. Changing it is a parent-driven rebuild.
  final int revision;

  @override
  State<NotificationCounter> createState() => _NotificationCounterState();
}

class _NotificationCounterState extends State<NotificationCounter> {
  int _count = 3;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'NotificationCounter',
      body: '$_count unread · parent revision ${widget.revision}',
      trailing: TextButton(
        onPressed: () => setState(() => _count++),
        child: const Text('Add notification'),
      ),
    );
  }
}

/// Activity list that can burst-update on its own.
class RecentActivity extends StatefulWidget {
  /// Creates the activity section.
  const RecentActivity({super.key});

  @override
  State<RecentActivity> createState() => _RecentActivityState();
}

class _RecentActivityState extends State<RecentActivity> {
  int _ticks = 1;
  Timer? _burst;

  @override
  void dispose() {
    _burst?.cancel();
    super.dispose();
  }

  void _startBurst() {
    _burst?.cancel();
    var remaining = 8;
    _burst = Timer.periodic(const Duration(milliseconds: 40), (timer) {
      if (!mounted || remaining == 0) {
        timer.cancel();
        return;
      }
      remaining -= 1;
      setState(() => _ticks++);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'RecentActivity',
      body: '$_ticks updates in this section',
      trailing: TextButton(
        onPressed: _startBurst,
        child: const Text('Burst updates'),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, this.trailing});

  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E0D6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body),
            if (trailing != null) ...[const SizedBox(height: 4), trailing!],
          ],
        ),
      ),
    );
  }
}
