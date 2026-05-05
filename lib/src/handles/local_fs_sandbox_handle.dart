// aq_sandbox/lib/src/handles/local_fs_sandbox_handle.dart

import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import '../contexts/local_fs_context.dart';
import '../contexts/simple_net_context.dart';
import '../contexts/simple_proc_context.dart';
import 'base_sandbox_handle.dart';

final class LocalFsSandboxHandle extends BaseSandboxHandle {
  final String workDir;

  /// true = этот sandbox владеет workDir и удаляет его при dispose.
  /// false = workDir принадлежит другому sandbox (agent), не удалять.
  final bool isOwned;

  LocalFsSandboxHandle(String sandboxId, this.workDir, {this.isOwned = true})
      : super(sandboxId, SandboxRuntimeType.localFs);

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

  @override
  Future<void> dispose({bool saveArtifacts = true}) async {
    status = SandboxStatus.disposing;
    if (isOwned && !saveArtifacts) {
      await Directory(workDir).delete(recursive: true);
    }
    status = SandboxStatus.disposed;
  }
}
