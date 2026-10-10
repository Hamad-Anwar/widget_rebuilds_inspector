import 'resource_sample.dart';
import 'resource_usage_stub.dart'
    if (dart.library.io) 'resource_usage_io.dart'
    as impl;

export 'resource_sample.dart';

/// Whether this process can report memory and app storage.
bool get resourceUsageSupported => impl.resourceUsageSupported;

/// Current process memory in bytes, or null when it cannot be read.
int? readProcessRamBytes() => impl.readProcessRamBytes();

/// Bytes saved by this app, or null when the folders cannot be read.
Future<int?> readAppStorageBytes() => impl.readAppStorageBytes();

/// Reads RAM and, when requested, the app's saved files.
Future<ResourceSample> readResourceUsage({bool includeStorage = true}) {
  return impl.readResourceUsage(includeStorage: includeStorage);
}
