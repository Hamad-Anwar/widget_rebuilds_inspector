/// A point-in-time reading of process memory and app file storage.
class ResourceSample {
  /// Creates a sample.
  const ResourceSample({
    this.ramBytes,
    this.storageBytes,
    this.measuredStorage = false,
  });

  /// Resident memory of this process, in bytes.
  ///
  /// Null when the platform does not report it.
  final int? ramBytes;

  /// Bytes stored in this app's support, cache, and documents folders.
  ///
  /// Null when storage was not measured on this sample, or when the folders
  /// could not be read. Check [measuredStorage].
  final int? storageBytes;

  /// Whether [storageBytes] was measured for this sample.
  final bool measuredStorage;
}
