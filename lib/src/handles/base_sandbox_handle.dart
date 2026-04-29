// aq_sandbox/lib/src/handles/base_sandbox_handle.dart

import 'package:aq_schema/sandbox.dart';
import 'package:aq_schema/tools.dart';

abstract base class BaseSandboxHandle implements ISandboxHandle {
  @override
  final String sandboxId;
  
  @override
  final SandboxRuntimeType sbRuntimeType;
  
  @override
  SandboxStatus status = SandboxStatus.creating;

  BaseSandboxHandle(this.sandboxId, this.sbRuntimeType);

  @override
  Future<RunContext> createContext({
    required List<ToolCapability> requestedCaps,
    required SandboxPolicy policy,
    required String runId,
  }) async {
    final grantedCaps = _negotiate(requestedCaps, policy);
    
    return RunContext(
      runId: runId,
      sandboxId: sandboxId,
      sessionId: runId,
      fs: grantedCaps.hasFs ? await createFsContext() : null,
      net: grantedCaps.hasNet ? await createNetContext(policy) : null,
      proc: grantedCaps.hasProc ? await createProcContext(policy) : null,
    );
  }

  _GrantedCaps _negotiate(List<ToolCapability> requested, SandboxPolicy policy) {
    final hasFs = requested.any((c) => c is FsReadCap || c is FsWriteCap) &&
        policy.allowedCaps.any((c) => c is FsReadCap || c is FsWriteCap);
    final hasNet = requested.any((c) => c is NetOutCap) &&
        policy.allowedCaps.any((c) => c is NetOutCap);
    final hasProc = requested.any((c) => c is ProcSpawnCap) &&
        policy.allowedCaps.any((c) => c is ProcSpawnCap);
    
    return _GrantedCaps(hasFs, hasNet, hasProc);
  }

  Future<IFsContext?> createFsContext();
  Future<INetContext?> createNetContext(SandboxPolicy policy);
  Future<IProcContext?> createProcContext(SandboxPolicy policy);

  @override
  Future<void> suspend() async => status = SandboxStatus.suspended;

  @override
  Future<void> resume() async => status = SandboxStatus.ready;
}

final class _GrantedCaps {
  final bool hasFs;
  final bool hasNet;
  final bool hasProc;
  _GrantedCaps(this.hasFs, this.hasNet, this.hasProc);
}
