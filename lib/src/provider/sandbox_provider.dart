// aq_sandbox/lib/src/provider/sandbox_provider.dart

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import 'package:uuid/uuid.dart';
import '../handles/in_memory_sandbox_handle.dart';
import '../handles/local_fs_sandbox_handle.dart';

final class SandboxProvider implements ISandboxProvider {
  final Map<String, ISandboxHandle> _sandboxes = {};
  final String _baseDir;

  SandboxProvider(this._baseDir);

  @override
  Future<ISandboxHandle> create(SandboxSpec spec) async {
    final id = const Uuid().v4();

    final handle = switch (spec.runtime) {
      SandboxRuntimeType.inMemory => InMemorySandboxHandle(id),
      SandboxRuntimeType.localFs => await _createLocalFs(id, spec.workDirOverride),
      _ => throw UnsupportedRuntimeError(spec.runtime),
    };

    handle.status = SandboxStatus.ready;
    _sandboxes[id] = handle;
    return handle;
  }

  Future<LocalFsSandboxHandle> _createLocalFs(String id, String? workDirOverride) async {
    final workDir = workDirOverride ?? '$_baseDir/$id';
    if (workDirOverride == null) {
      await Directory(workDir).create(recursive: true);
    }
    return LocalFsSandboxHandle(id, workDir, isOwned: workDirOverride == null);
  }

  @override
  Future<ISandboxHandle?> get(String sandboxId) async => _sandboxes[sandboxId];

  @override
  Future<List<SandboxRuntimeType>> availableRuntimes() async => [
        SandboxRuntimeType.inMemory,
        SandboxRuntimeType.localFs,
      ];
}

final class UnsupportedRuntimeError implements Exception {
  final SandboxRuntimeType runtime;
  UnsupportedRuntimeError(this.runtime);
  @override
  String toString() => 'Unsupported runtime: $runtime';
}
