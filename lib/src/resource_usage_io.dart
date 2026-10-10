import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'resource_sample.dart';

/// VM targets can read the process resident set and app directories.
bool get resourceUsageSupported => true;

/// Current process memory, in bytes. Null when the platform reports nothing.
int? readProcessRamBytes() {
  final rss = ProcessInfo.currentRss;
  return rss > 0 ? rss : null;
}

/// Bytes in this app's support, cache, and documents folders.
Future<int?> readAppStorageBytes() => _appStorageBytes();

/// Reads current process memory and, when [includeStorage] is true, app files.
Future<ResourceSample> readResourceUsage({bool includeStorage = true}) async {
  int? storage;
  var measuredStorage = false;
  if (includeStorage) {
    measuredStorage = true;
    storage = await _appStorageBytes();
  }
  return ResourceSample(
    ramBytes: readProcessRamBytes(),
    storageBytes: storage,
    measuredStorage: measuredStorage,
  );
}

Future<int?> _appStorageBytes() async {
  try {
    final dirs = await _appDirectories();
    if (dirs.isEmpty) return null;
    var total = 0;
    for (final directory in _roots(dirs)) {
      total += await _sizeOf(directory);
    }
    return total;
  } on Object {
    return null;
  }
}

Future<List<Directory>> _appDirectories() async {
  final support = await _tryDirectory(getApplicationSupportDirectory);
  final cache = await _tryDirectory(getApplicationCacheDirectory);
  final documents = await _tryDirectory(getApplicationDocumentsDirectory);
  final temp = await _tryDirectory(getTemporaryDirectory);
  final scoped = <Directory>[
    ?support,
    ?cache,
    if (documents != null && !_isHomeDocuments(documents)) documents,
  ];
  if (temp != null && _livesWithApp(temp, scoped)) scoped.add(temp);
  return scoped;
}

Future<Directory?> _tryDirectory(Future<Directory> Function() resolve) async {
  try {
    final directory = await resolve();
    if (!await directory.exists()) return null;
    return directory;
  } on Object {
    return null;
  }
}

/// `~/Documents` on an unsandboxed desktop is the user's files, not the app's.
bool _isHomeDocuments(Directory directory) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return false;
  return directory.absolute.path == _join(home, 'Documents');
}

bool _livesWithApp(Directory directory, List<Directory> appDirs) {
  final path = directory.absolute.path;
  for (final appDir in appDirs) {
    final parent = appDir.parent.absolute.path;
    if (_isInside(parent, path) || _isInside(appDir.absolute.path, path)) {
      return true;
    }
  }
  return false;
}

List<Directory> _roots(List<Directory> directories) {
  final sorted = [...directories]
    ..sort((a, b) => a.absolute.path.length.compareTo(b.absolute.path.length));
  final roots = <Directory>[];
  for (final directory in sorted) {
    final path = directory.absolute.path;
    final nested = roots.any((root) => _isInside(root.absolute.path, path));
    if (!nested) roots.add(directory);
  }
  return roots;
}

bool _isInside(String parent, String child) {
  if (child == parent) return true;
  final separator = parent.contains('\\') ? '\\' : '/';
  final prefix = parent.endsWith(separator) ? parent : '$parent$separator';
  return child.startsWith(prefix);
}

String _join(String parent, String child) {
  final separator = parent.contains('\\') ? '\\' : '/';
  if (parent.endsWith(separator)) return '$parent$child';
  return '$parent$separator$child';
}

Future<int> _sizeOf(Directory directory) async {
  var total = 0;
  var seen = 0;
  await for (final entity in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    seen += 1;
    if (seen > 20000) break;
    try {
      total += await entity.length();
    } on Object {
      // The file can disappear between listing and reading its length.
    }
  }
  return total;
}
