part of '../widget_rebuilds_inspector.dart';

const Set<String> _blockedWidgetTypes = {
  'RebuildInspector',
  'WidgetRebuildInspector',
};

/// Widgets that belong to the inspector UI. Automatic mode must ignore them,
/// or the panel records its own refreshes and the counts climb forever.
const Set<String> _inspectorWidgetNames = {
  '_RebuildOverlay',
  '_CollapsedChip',
  '_InspectorChrome',
  '_FlashBarrier',
  '_FlashLayer',
  '_SwitchRow',
  '_TextAction',
  '_BandChip',
};

const Set<String> _commonWidgetTypes = {
  'AbsorbPointer',
  'Actions',
  'Align',
  'AnimatedOpacity',
  'AnimatedPadding',
  'AnimatedPositioned',
  'AnimatedSize',
  'AppBar',
  'AspectRatio',
  'BackdropFilter',
  'BottomNavigationBar',
  'Builder',
  'Card',
  'Center',
  'Checkbox',
  'Chip',
  'CircularProgressIndicator',
  'ClipOval',
  'ClipPath',
  'ClipRRect',
  'ClipRect',
  'ColoredBox',
  'Column',
  'ConstrainedBox',
  'Container',
  'CustomPaint',
  'CustomScrollView',
  'DecoratedBox',
  'DefaultTextStyle',
  'Directionality',
  'Divider',
  'Drawer',
  'EditableText',
  'ElevatedButton',
  'ExcludeSemantics',
  'Expanded',
  'FadeTransition',
  'FilledButton',
  'FittedBox',
  'Flex',
  'Flexible',
  'FloatingActionButton',
  'Focus',
  'FocusScope',
  'Form',
  'FractionallySizedBox',
  'GestureDetector',
  'GridView',
  'Hero',
  'Icon',
  'IconButton',
  'IconTheme',
  'IgnorePointer',
  'Image',
  'IndexedStack',
  'InkWell',
  'IntrinsicHeight',
  'IntrinsicWidth',
  'KeyedSubtree',
  'LimitedBox',
  'LinearProgressIndicator',
  'ListBody',
  'Listener',
  'ListTile',
  'ListView',
  'Material',
  'MediaQuery',
  'ModalBarrier',
  'MouseRegion',
  'NavigationBar',
  'Navigator',
  'Offstage',
  'Opacity',
  'OutlinedButton',
  'OverflowBox',
  'Overlay',
  'Padding',
  'PageView',
  'PhysicalModel',
  'Positioned',
  'Radio',
  'RawGestureDetector',
  'RepaintBoundary',
  'RichText',
  'RotatedBox',
  'Row',
  'SafeArea',
  'Scaffold',
  'ScaleTransition',
  'Scrollbar',
  'Scrollable',
  'Semantics',
  'Shortcuts',
  'SingleChildScrollView',
  'SizeTransition',
  'SizedBox',
  'SizedOverflowBox',
  'Slider',
  'SlideTransition',
  'SliverFillRemaining',
  'SliverGrid',
  'SliverList',
  'SliverPadding',
  'SliverToBoxAdapter',
  'Spacer',
  'Stack',
  'StatefulBuilder',
  'Switch',
  'TabBar',
  'TabBarView',
  'Text',
  'TextButton',
  'TextField',
  'TextFormField',
  'Title',
  'Transform',
  'VerticalDivider',
  'Visibility',
  'Wrap',
};

const List<String> _commonWidgetPrefixes = [
  'AnimatedBuilder',
  'FutureBuilder',
  'LayoutBuilder',
  'ListenableBuilder',
  'NotificationListener',
  'OrientationBuilder',
  'StreamBuilder',
  'ValueListenableBuilder',
];

/// Whether [type] is a framework or very common widget that automatic mode hides.
bool _isCommonWidgetType(String type) {
  if (_commonWidgetTypes.contains(type)) return true;
  for (final prefix in _commonWidgetPrefixes) {
    if (type.startsWith(prefix)) return true;
  }
  return false;
}

bool _includeAutomaticWidget(
  Widget widget, {
  required bool userWidgetsOnly,
  required bool ignoreCommonWidgets,
  required bool creationTracked,
}) {
  final type = widget.runtimeType.toString();
  if (_blockedWidgetTypes.contains(type) ||
      _inspectorWidgetNames.contains(type)) {
    return false;
  }
  if (ignoreCommonWidgets && _isCommonWidgetType(type)) return false;
  if (!userWidgetsOnly) return !type.startsWith('_');
  if (creationTracked) return debugIsWidgetLocalCreation(widget);
  return !type.startsWith('_');
}
