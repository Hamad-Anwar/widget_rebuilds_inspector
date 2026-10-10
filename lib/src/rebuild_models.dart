part of '../widget_rebuilds_inspector.dart';

/// How busy a monitored widget looks in the current session.
enum RebuildBand {
  /// No builds recorded since the last reset.
  idle,

  /// Under [RebuildThresholds.moderateAfter] and the moderate rate.
  low,

  /// Worth a look, but not yet in the frequent band.
  moderate,

  /// At or above the frequent count or the frequent rate.
  frequent;

  /// Short label used in the overlay.
  String get label => switch (this) {
    RebuildBand.idle => 'Idle',
    RebuildBand.low => 'Low',
    RebuildBand.moderate => 'Moderate',
    RebuildBand.frequent => 'Frequent',
  };

  /// Color used for badges, flashes, and chips.
  Color get color => switch (this) {
    RebuildBand.idle => const Color(0xFF6B7280),
    RebuildBand.low => const Color(0xFF1F8A4C),
    RebuildBand.moderate => const Color(0xFFC47B09),
    RebuildBand.frequent => const Color(0xFFD63A46),
  };
}

/// Why a recorded build ran.
///
/// These causes describe the widget tree, not frame time. None of them prove
/// that the work was wasted.
enum RebuildCause {
  /// The element mounted and built for the first time.
  initialBuild,

  /// An ancestor rebuilt and pushed a new configuration into this slot.
  parentRebuild,

  /// The wrapped widget rebuilt without its inspector slot rebuilding.
  ///
  /// Typical sources are [State.setState], an inherited dependency, and a
  /// direct [Element.markNeedsBuild].
  childRebuild;

  /// Short label used in the overlay and reports.
  String get label => switch (this) {
    RebuildCause.initialBuild => 'Initial build',
    RebuildCause.parentRebuild => 'Parent rebuild',
    RebuildCause.childRebuild => 'Child rebuild',
  };
}

/// Where a row in the dashboard came from.
enum RebuildSource {
  /// A [RebuildInspector] the app inserted around a widget.
  instrumented,

  /// A user widget observed through Flutter's debug rebuild hook.
  automatic;

  /// Short label used in the overlay.
  String get label => switch (this) {
    RebuildSource.instrumented => 'Instrumented',
    RebuildSource.automatic => 'Detected',
  };
}

/// Count and rate cutoffs that map a widget onto a [RebuildBand].
///
/// The stricter of the two signals wins. Defaults put 31 rebuilds in
/// [RebuildBand.moderate] and 47 in [RebuildBand.frequent].
@immutable
class RebuildThresholds {
  /// Creates thresholds.
  const RebuildThresholds({
    this.moderateAfter = 10,
    this.frequentAfter = 40,
    this.moderatePerSecond = 4,
    this.frequentPerSecond = 10,
    this.rateWindow = const Duration(seconds: 3),
  }) : assert(moderateAfter >= 1),
       assert(frequentAfter > moderateAfter),
       assert(moderatePerSecond > 0),
       assert(frequentPerSecond > moderatePerSecond);

  /// Builds at or above this count are at least [RebuildBand.moderate].
  final int moderateAfter;

  /// Builds at or above this count are [RebuildBand.frequent].
  final int frequentAfter;

  /// Rates at or above this are at least [RebuildBand.moderate].
  final double moderatePerSecond;

  /// Rates at or above this are [RebuildBand.frequent].
  final double frequentPerSecond;

  /// Sliding window used to compute [RebuildWidgetStats.buildsPerSecond].
  final Duration rateWindow;

  /// Returns the busier of the count band and the rate band.
  RebuildBand bandFor({
    required int buildCount,
    required double buildsPerSecond,
  }) {
    if (buildCount <= 0) return RebuildBand.idle;
    final byCount = buildCount >= frequentAfter
        ? RebuildBand.frequent
        : buildCount >= moderateAfter
        ? RebuildBand.moderate
        : RebuildBand.low;
    final byRate = buildsPerSecond >= frequentPerSecond
        ? RebuildBand.frequent
        : buildsPerSecond >= moderatePerSecond
        ? RebuildBand.moderate
        : RebuildBand.low;
    return byCount.index >= byRate.index ? byCount : byRate;
  }

  @override
  bool operator ==(Object other) {
    return other is RebuildThresholds &&
        other.moderateAfter == moderateAfter &&
        other.frequentAfter == frequentAfter &&
        other.moderatePerSecond == moderatePerSecond &&
        other.frequentPerSecond == frequentPerSecond &&
        other.rateWindow == rateWindow;
  }

  @override
  int get hashCode => Object.hash(
    moderateAfter,
    frequentAfter,
    moderatePerSecond,
    frequentPerSecond,
    rateWindow,
  );
}

/// Immutable snapshot of one monitored widget or widget type.
@immutable
class RebuildWidgetStats {
  /// Creates a snapshot. Prefer reading these from [RebuildInspectorController.stats].
  const RebuildWidgetStats({
    required this.id,
    required this.name,
    required this.source,
    required this.buildCount,
    required this.initialBuildCount,
    required this.parentRebuildCount,
    required this.childRebuildCount,
    required this.buildsPerSecond,
    required this.band,
    required this.lastCause,
    required this.recentBuckets,
    this.location,
    this.lastBuildAt,
    this.baselineBuildCount,
  });

  /// Stable id for this row. Instrumented rows are per element.
  final String id;

  /// [RebuildInspector.name], or the widget's runtime type in automatic mode.
  final String name;

  /// Optional file or feature label supplied to [RebuildInspector.location].
  final String? location;

  /// Whether the row is an explicit wrapper or an automatic group.
  final RebuildSource source;

  /// All recorded builds, including the initial mount for instrumented widgets.
  final int buildCount;

  /// Mount builds. Automatic rows leave this at zero and start at the first rebuild.
  final int initialBuildCount;

  /// Builds caused by an ancestor updating this slot.
  final int parentRebuildCount;

  /// Builds of the wrapped widget that were not caused by the inspector slot.
  final int childRebuildCount;

  /// Builds inside [RebuildThresholds.rateWindow], divided by that window.
  final double buildsPerSecond;

  /// Band for [buildCount] and [buildsPerSecond] under the active thresholds.
  final RebuildBand band;

  /// Cause of the most recent recorded build.
  final RebuildCause lastCause;

  /// When the most recent recorded build ran.
  final DateTime? lastBuildAt;

  /// Count captured by [RebuildInspectorController.markBaseline], if this id existed.
  final int? baselineBuildCount;

  /// Per-second build counts for the last few seconds, oldest first.
  final List<int> recentBuckets;

  /// `buildCount - baseline`, or null when this row was not in the baseline.
  int? get deltaFromBaseline {
    final baseline = baselineBuildCount;
    if (baseline == null) return null;
    return buildCount - baseline;
  }
}

/// One build event kept for the timeline and exported reports.
@immutable
class RebuildEvent {
  /// Creates an event.
  const RebuildEvent({
    required this.name,
    required this.source,
    required this.cause,
    required this.occurredAt,
  });

  /// Widget name at the time of the event.
  final String name;

  /// Instrumented wrapper or automatic detection.
  final RebuildSource source;

  /// Why this build was recorded.
  final RebuildCause cause;

  /// When the build was recorded.
  final DateTime occurredAt;
}

/// Change in one widget's build count since [RebuildInspectorController.markBaseline].
@immutable
class RebuildDelta {
  /// Creates a delta.
  const RebuildDelta({
    required this.id,
    required this.name,
    required this.after,
    this.before,
  });

  /// Stats id.
  final String id;

  /// Display name.
  final String name;

  /// Count when the baseline was marked. Null if the widget appeared later.
  final int? before;

  /// Count at comparison time.
  final int after;

  /// [after] minus [before], treating a missing baseline as zero.
  int get change => after - (before ?? 0);

  /// Whether [before] was absent from the baseline.
  bool get isNew => before == null;
}

/// Result of [RebuildInspectorController.compareToBaseline].
@immutable
class RebuildComparison {
  /// Creates a comparison.
  const RebuildComparison({
    required this.label,
    required this.capturedAt,
    required this.deltas,
  });

  /// Label passed to [RebuildInspectorController.markBaseline].
  final String label;

  /// When the baseline was marked.
  final DateTime capturedAt;

  /// One entry per widget in the baseline or the current session.
  final List<RebuildDelta> deltas;
}
