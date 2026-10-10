# widget_rebuilds_inspector

See which widgets rebuild, while you are still in the app.

<p align="center">
  <img
    src="https://raw.githubusercontent.com/Hamad-Anwar/widget_rebuilds_inspector/main/demo.mp4"
    alt="Widget Rebuild Inspector Demo"
    width="360"
  />
</p>

A debug-only overlay for Flutter. Wrap the widgets you care about, use the screen as usual, and read the count on the widget itself. Each count says whether a parent pushed a new configuration in, or the child rebuilt on its own.

| On the widget | In the panel | After a refactor |
| --- | --- | --- |
| A paint-only badge and a short flash on the bounds | Rows sorted by how busy they are, with Low, Moderate, and Frequent | A baseline you can compare, then export as Markdown or JSON |

Rebuild counts are diagnostics. A high count does not by itself mean a frame is expensive, and one rebuild can still be the expensive one.

## Install

```yaml
dependencies:
  widget_rebuilds_inspector: ^1.0.0
```

```sh
flutter pub get
```

Dart `^3.10.1`. Flutter `>=3.38.0`.

## Quick start

Put the overlay above the app, then name the widgets you want to watch.

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:widget_rebuilds_inspector/widget_rebuilds_inspector.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      builder: (context, child) {
        return WidgetRebuildInspector(
          enabled: kDebugMode,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const InboxPage(),
    );
  }
}
```

```dart
Column(
  children: [
    RebuildInspector(name: 'ProfileHeader', child: ProfileHeader()),
    RebuildInspector(name: 'UserInformation', child: UserInformation()),
    RebuildInspector(name: 'NotificationCounter', child: NotificationCounter()),
    RebuildInspector(name: 'RecentActivity', child: RecentActivity()),
  ],
)
```

`showCounter` and `highlightRebuilds` default to true. The badge is painted on top of the child, so it does not change layout or add another build.

`enabled` defaults to `kDebugMode`. In release the inspector returns `child` and does not install a hook.

## What a row is counting

`RebuildInspector` counts how often that child builds.

| Cause | What happened | What to try |
| --- | --- | --- |
| Initial build | The wrapped widget mounted. | Expected when the screen opens. |
| Parent rebuild | An ancestor rebuilt and this slot received a new widget. | Pass a `const` child, or split the parent so this slot stays the same instance. |
| Child rebuild | The child built again on its own. | Look at `setState`, an `InheritedWidget`, or `markNeedsBuild` inside that widget. |

An identical child is skipped. A `const` widget that Flutter does not rebuild leaves the counter still. That is the result you want after caching a child or splitting a `build` method.

```dart
// This child is skipped when the parent rebuilds.
RebuildInspector(
  name: 'Frozen',
  child: const ProfileHeader(),
)
```

Child-originated counts use Flutter's debug rebuild hook, so they show up in debug builds. Parent-driven counts keep working when that hook is already taken.

A wrapper counts the child you gave it. A `setState` inside a nested stateful widget belongs to that nested widget. Wrap that widget, or turn Automatic on, to see it.

## The panel

The panel sits at the bottom right. Tap the **Rebuilds** chip to open it. The chip shows the busiest count, such as `Rebuilds · 4×`.

| Control | What it does |
| --- | --- |
| Automatic | Counts widgets you did not wrap. Off until you turn it on. |
| Hotspots | Outlines widgets that are rebuilding a lot. Full-screen rectangles are left alone. |
| Pause | Freezes the counts. The button switches to Resume. |
| Reset | Clears the current counts and keeps the baseline. |
| Close | Collapses the panel back to the chip. |
| RAM | This process's resident memory, about once a second. |
| Storage | Files this app has saved in its support, cache, and documents folders. |

The panel does not count its own rebuilds.

**RAM** comes from the current process (`ProcessInfo.currentRss` where the VM provides it). **Storage** is the size of this app's own folders, not the disk. On web those two readouts are hidden. A number that moves a little on a quiet screen is normal: the engine, the garbage collector, and this once-a-second sample all touch memory. A leak is a floor that climbs and stays up.

## Frequency

A row is **Low**, **Moderate**, or **Frequent**. The busier of two signals wins.

| Signal | Moderate | Frequent |
| --- | --- | --- |
| Builds in this session | 10 | 40 |
| Builds per second, over 3 seconds | 4/s | 10/s |

31 builds spread across a session land in Moderate. 47 lands in Frequent. A short burst can reach Frequent on rate before the total does.

```dart
WidgetRebuildInspector(
  enabled: kDebugMode,
  thresholds: const RebuildThresholds(
    moderateAfter: 20,
    frequentAfter: 60,
    moderatePerSecond: 5,
    frequentPerSecond: 12,
  ),
  onFrequentRebuild: (stats) {
    debugPrint('${stats.name} is rebuilding a lot');
  },
  child: child ?? const SizedBox.shrink(),
)
```

`onFrequentRebuild` runs once, when a row first enters Frequent.

## Before and after

Mark a baseline, repeat the same gesture, then compare. `reset()` clears the live counts and leaves the baseline in place.

```dart
final inspector = RebuildInspectorController.instance;

inspector.markBaseline('Before const split');
// Repeat the interaction.
final comparison = inspector.compareToBaseline();
debugPrint(inspector.exportMarkdown());
```

`exportMarkdown()` is a table you can paste into a pull request. `exportJson()` is the same report, including the baseline when one exists. `clearBaseline()` drops it.

## Automatic detection

Wrapped widgets are exact. Automatic mode is broader. It stays off until **Automatic** is on, or you pass `automaticTracking: true`.

```dart
WidgetRebuildInspector(
  enabled: kDebugMode,
  automaticTracking: true,
  userWidgetsOnly: true,
  ignoreCommonWidgets: true,
  child: child ?? const SizedBox.shrink(),
)
```

In debug builds it listens to `debugOnRebuildDirtyWidget` and groups later rebuilds by widget type. With the defaults it keeps widgets created in your app and hides common layout and Material widgets. The first mount is not counted, so opening a screen does not look like a hotspot.

`userWidgetsOnly` needs widget creation tracking, which debug builds already turn on. `ignoreCommonWidgets` hides types such as `Padding`, `Column`, and `Text`.

**Hotspots** flashes detected widgets that reach Frequent. `highlightHotspots: true` starts with that outline on.

Automatic detection and DevTools **Track Widget Rebuilds** share one Flutter callback. When DevTools owns it, parent-driven `RebuildInspector` counts still work, and the panel says automatic detection is paused.

## What this is for

DevTools already tracks rebuilds from the IDE. This package keeps the count on the running screen: the name you chose, the parent-or-child cause, a flash on the real widget, and a before-and-after delta for the same gesture.

It does not measure paint, layout, or frame time. `highlightRebuilds` repaints the wrapped subtree for a fraction of a second so the border is visible. That repaint is not added to the count.

## Example

The `example/` app is a four-section inbox.

| Button | What you should see |
| --- | --- |
| Simulate parent rebuild | Every non-const section counts a parent rebuild. A `const` section stays still. |
| Add notification | `NotificationCounter` counts a child rebuild. |
| Burst updates | `RecentActivity` climbs on its own. |

```sh
cd example
flutter run
```

## Options

### `WidgetRebuildInspector`

| Parameter | Default | Role |
| --- | --- | --- |
| `enabled` | `kDebugMode` | `false` returns `child` with no hook and no panel. |
| `showOverlay` | `true` | Paints the panel. |
| `initiallyExpanded` | `false` | Starts on the chip, or open. |
| `automaticTracking` | `false` | Records widgets you did not wrap. |
| `userWidgetsOnly` | `true` | Keeps widgets created in the app target. |
| `ignoreCommonWidgets` | `true` | Hides common framework widgets in automatic mode. |
| `highlightHotspots` | `false` | Outlines frequent detected widgets. |
| `thresholds` | `RebuildThresholds()` | Count and rate cutoffs. |
| `controller` | owned | Pass one in when you want baseline and export from your own code. |
| `onFrequentRebuild` | null | Called the first time a row becomes Frequent. |

### `RebuildInspector`

| Parameter | Default | Role |
| --- | --- | --- |
| `name` | required | Label in the badge, the panel, and the export. |
| `child` | required | The widget to count. |
| `showCounter` | `true` | Paints the count. |
| `highlightRebuilds` | `true` | Flashes the bounds after the initial mount. |
| `highlightColor` | band color | Overrides the Low / Moderate / Frequent color. |
| `location` | null | Extra label stored on the report row. |
| `enabled` | inherited | Overrides the scope, then `kDebugMode`. |
| `controller` | inherited | Overrides the nearest `WidgetRebuildInspector`. |
