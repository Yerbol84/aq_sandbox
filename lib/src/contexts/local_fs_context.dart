// aq_sandbox/lib/src/contexts/local_fs_context.dart

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import 'package:path/path.dart' as p;

final class LocalFsContext implements IFsContext {
  final String _workDir;

  LocalFsContext(this._workDir);

  String _resolve(String relativePath) {
    final resolved = p.normalize(p.join(_workDir, relativePath));
    if (resolved != _workDir && !p.isWithin(_workDir, resolved)) {
      throw PathEscapeError(relativePath);
    }
    return resolved;
  }

  @override
  Future<String> read(String relativePath) async {
    final file = File(_resolve(relativePath));
    return await file.readAsString();
  }

  @override
  Future<void> write(String relativePath, String content) async {
    final file = File(_resolve(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeBytes(String relativePath, List<int> bytes) async {
    final file = File(_resolve(relativePath));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<List<String>> list({String? subDir}) async {
    final dir = Directory(_resolve(subDir ?? '.'));
    final entries = await dir.list(recursive: true).toList();
    return entries.whereType<File>().map((f) => p.relative(f.path, from: _workDir)).toList();
  }

  @override
  Future<bool> exists(String relativePath) async {
    return await File(_resolve(relativePath)).exists();
  }

  @override
  Future<void> delete(String relativePath) async {
    await File(_resolve(relativePath)).delete();
  }
}

final class PathEscapeError implements Exception {
  final String path;
  PathEscapeError(this.path);
  @override
  String toString() => 'Path escape attempt: $path';
}
