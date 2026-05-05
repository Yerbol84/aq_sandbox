// aq_sandbox/lib/src/contexts/in_memory_fs_context.dart

import 'dart:convert';
import 'package:aq_schema/sandbox.dart';

final class InMemoryFsContext implements IFsContext {
  final Map<String, List<int>> _files = {};
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> dispose() async => _disposed = true;

  @override
  Future<String> read(String relativePath) async {
    final bytes = _files[relativePath];
    if (bytes == null) throw FileNotFoundError(relativePath);
    return utf8.decode(bytes);
  }

  @override
  Future<void> write(String relativePath, String content) async {
    _files[relativePath] = utf8.encode(content);
  }

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    _files[relativePath] = bytes;
  }

  @override
  Future<List<String>> list({String? subDir}) async {
    final prefix = subDir != null ? '$subDir/' : '';
    return _files.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<bool> exists(String relativePath) async =>
      _files.containsKey(relativePath);

  @override
  Future<void> delete(String relativePath) async => _files.remove(relativePath);
}

final class FileNotFoundError implements Exception {
  final String path;
  FileNotFoundError(this.path);
  @override
  String toString() => 'File not found: $path';
}
