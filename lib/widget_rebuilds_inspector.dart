/// In-app widget rebuild inspector for Flutter debug builds.
///
/// Wrap a widget with [RebuildInspector] to count that widget, or wrap the
/// app with [WidgetRebuildInspector] for an overlay, automatic detection, and
/// before/after comparison.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'src/resource_usage.dart';

part 'src/rebuild_models.dart';
part 'src/rebuild_filters.dart';
part 'src/rebuild_controller.dart';
part 'src/rebuild_monitor.dart';
part 'src/rebuild_overlay.dart';
part 'src/widget_rebuild_inspector.dart';

/// Disclaimer included in the overlay and in exported reports.
///
/// A rebuild count is not a profile. Expensive work can hide in a widget that
/// rebuilds once, and a high count can be cheap.
const String rebuildInspectorDisclaimer =
    'Rebuild counts are debug diagnostics. A high count does not by itself '
    'mean a frame is expensive or that the rebuild was unnecessary.';
