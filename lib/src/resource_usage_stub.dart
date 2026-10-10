import 'resource_sample.dart';

/// Web and other targets without `dart:io` cannot read process memory.
bool get resourceUsageSupported => false;

/// Web builds have no process-memory API.
int? readProcessRamBytes() => null;

/// Web builds have no app-directory API.
Future<int?> readAppStorageBytes() async => null;

/// Returns an empty sample. Web builds have no process-memory API.
Future<ResourceSample> readResourceUsage({bool includeStorage = true}) async {
  return const ResourceSample();
}
