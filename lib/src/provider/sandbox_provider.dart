// aq_sandbox/lib/src/provider/sandbox_provider.dart

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import 'package:aq_schema/tools.dart';
import 'package:uuid/uuid.dart';
import '../handles/in_memory_sandbox_handle.dart';
import '../handles/local_fs_sandbox_handle.dart';
import '../handles/docker_sandbox_handle.dart';

final class SandboxProvider implements ISandboxProvider {
  final Map<String, ISandboxHandle> _sandboxes = {};
  final String _baseDir;

  /// Docker image используемый по умолчанию для docker runtime.
  final String dockerImage;

  SandboxProvider(this._baseDir, {this.dockerImage = 'alpine:latest'});

  @override
  Future<ISandboxHandle> create(SandboxSpec spec) async {
    final id = const Uuid().v4();

    // P-12: LocalFS не обеспечивает OS-level isolation.
    // ProcSpawnCap с localFs runtime — процесс не ограничен chroot/namespace.
    // TECH_DEBT(TD-04): заменить на SandboxIsolationLevel когда будет chroot/Docker.
    if (spec.runtime == SandboxRuntimeType.localFs &&
        spec.policy.allowedCaps.any((c) => c is ProcSpawnCap)) {
      // ignore: avoid_print
      print('[WARNING] SandboxProvider: ProcSpawnCap requested with localFs runtime. '
          'LocalFS does NOT provide OS-level isolation — process can escape sandbox. '
          'Use Docker runtime for untrusted code.');
    }

    final handle = switch (spec.runtime) {
      SandboxRuntimeType.inMemory => InMemorySandboxHandle(id),
      SandboxRuntimeType.localFs => await _createLocalFs(id, spec.workDirOverride),
      SandboxRuntimeType.docker  => await _createDocker(id, spec),
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

  Future<DockerSandboxHandle> _createDocker(String id, SandboxSpec spec) async {
    final workDir = '$_baseDir/$id';
    await Directory(workDir).create(recursive: true);
    return DockerSandboxHandle(id, workDir, image: dockerImage);
  }

  @override
  Future<ISandboxHandle?> get(String sandboxId) async => _sandboxes[sandboxId];

  /// P-03 fix: удалить disposed sandbox из карты.
  @override
  Future<void> release(String sandboxId) async {
    _sandboxes.remove(sandboxId);
  }

  @override
  Future<List<SandboxRuntimeType>> availableRuntimes() async => [
        SandboxRuntimeType.inMemory,
        SandboxRuntimeType.localFs,
        SandboxRuntimeType.docker,
      ];
}

final class UnsupportedRuntimeError implements Exception {
  final SandboxRuntimeType runtime;
  UnsupportedRuntimeError(this.runtime);
  @override
  String toString() => 'Unsupported runtime: $runtime';
}
