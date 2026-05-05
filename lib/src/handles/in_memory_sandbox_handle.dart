// aq_sandbox/lib/src/handles/in_memory_sandbox_handle.dart

import 'package:aq_schema/sandbox.dart';
import '../contexts/in_memory_fs_context.dart';
import '../contexts/simple_net_context.dart';
import 'base_sandbox_handle.dart';

final class InMemorySandboxHandle extends BaseSandboxHandle {
  InMemorySandboxHandle(String sandboxId) : super(sandboxId, SandboxRuntimeType.inMemory);

  @override
  Future<IWritableFsContext?> createFsContext() async => InMemoryFsContext();

  @override
  Future<INetContext?> createNetContext(SandboxPolicy policy) async {
    final hosts = policy.network?.allowedHosts.toSet() ?? {'*'};
    return SimpleNetContext(hosts);
  }

  @override
  Future<IProcContext?> createProcContext(SandboxPolicy policy) async => null;

  @override
  Future<void> dispose({bool saveArtifacts = true}) async {
    status = SandboxStatus.disposed;
  }
}
