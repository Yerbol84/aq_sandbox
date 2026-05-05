// aq_sandbox/lib/src/handles/docker_sandbox_handle.dart
//
// Docker-based sandbox handle.
// P-09: использует Docker HTTP API вместо docker CLI.
// TECH_DEBT(TD-03) закрыт.

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import '../contexts/local_fs_context.dart';
import '../contexts/simple_net_context.dart';
import '../contexts/simple_proc_context.dart';
import '../docker/docker_client.dart';
import 'base_sandbox_handle.dart';

export '../docker/docker_client.dart' show DockerApiException;

/// Sandbox handle backed by a Docker container.
///
/// Создаёт контейнер при первом [startContainer], монтирует workDir как volume.
final class DockerSandboxHandle extends BaseSandboxHandle {
  final String workDir;
  final String image;
  final Map<String, String> extraEnv;
  final DockerClient _docker;

  String? _containerId;

  DockerSandboxHandle(
    String sandboxId,
    this.workDir, {
    required this.image,
    this.extraEnv = const {},
    DockerClient? docker,
  })  : _docker = docker ?? DockerClient(),
        super(sandboxId, SandboxRuntimeType.docker);

  @override
  Future<IWritableFsContext?> createFsContext() async => LocalFsContext(workDir);

  @override
  Future<INetContext?> createNetContext(SandboxPolicy policy) async {
    final hosts = policy.network?.allowedHosts.toSet() ?? {'*'};
    return SimpleNetContext(hosts);
  }

  @override
  Future<IProcContext?> createProcContext(SandboxPolicy policy) async {
    final binaries = policy.allowedBinaries ?? {};
    return SimpleProcContext(binaries, workDir);
  }

  /// Запустить контейнер (если ещё не запущен).
  Future<String> startContainer({
    List<String> command = const [],
    Duration? timeout,
  }) async {
    if (_containerId != null) return _containerId!;

    await Directory(workDir).create(recursive: true);

    final env = {
      'AQ_WORK_DIR': '/workspace',
      'AQ_SANDBOX_ID': sandboxId,
      ...extraEnv,
    };

    final id = await _docker.containerCreate(
      image: image,
      name: 'aq-sandbox-$sandboxId',
      binds: ['$workDir:/workspace'],
      workingDir: '/workspace',
      env: env,
      cmd: command,
      stopTimeout: timeout?.inSeconds,
    );

    await _docker.containerStart(id);
    _containerId = id;
    status = SandboxStatus.ready;
    return id;
  }

  /// Выполнить команду внутри контейнера.
  Future<String> exec(List<String> command) async {
    final id = _containerId;
    if (id == null) throw StateError('Container not started');
    return _docker.containerExec(id, command);
  }

  @override
  Future<void> suspend() async {
    if (_containerId != null) {
      await _docker.containerPause(_containerId!);
    }
    status = SandboxStatus.suspended;
  }

  @override
  Future<void> resume() async {
    if (_containerId != null) {
      await _docker.containerUnpause(_containerId!);
    }
    status = SandboxStatus.ready;
  }

  @override
  Future<void> dispose({bool saveArtifacts = true}) async {
    status = SandboxStatus.disposing;
    if (_containerId != null) {
      await _docker.containerRemove(_containerId!);
      _containerId = null;
    }
    if (!saveArtifacts) {
      final dir = Directory(workDir);
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    status = SandboxStatus.disposed;
  }
}
