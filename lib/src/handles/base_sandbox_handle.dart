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
  Future<(RunContext, SandboxResources)> createContext({
    required List<ToolCapability> requestedCaps,
    required SandboxPolicy policy,
    required String runId,
  }) async {
    final grantedCaps = _negotiate(requestedCaps, policy);

    final fsCtx  = (grantedCaps.hasRead || grantedCaps.hasWrite) ? await createFsContext() : null;
    final netCtx  = grantedCaps.hasNet  ? await createNetContext(policy)  : null;
    final procCtx = grantedCaps.hasProc ? await createProcContext(policy) : null;

    final resources = SandboxResources(
      fsRead:  fsCtx,
      fsWrite: grantedCaps.hasWrite ? fsCtx : null,
      net:     netCtx,
      proc:    procCtx,
    );

    final context = RunContext(
      runId:     runId,
      sandboxId: sandboxId,
      sessionId: runId,
      policy:    policy,
      sandboxResources: resources,
    );

    return (context, resources);
  }

  /// S-01 fix: проверяем совместимость path patterns, не только типы.
  _GrantedCaps _negotiate(List<ToolCapability> requested, SandboxPolicy policy) {
    const matcher = DefaultCapabilityMatcher();

    bool isGranted(ToolCapability req) =>
        policy.allowedCaps.any((g) => matcher.allows(req, g));

    final hasRead  = requested.whereType<FsReadCap>().any(isGranted);
    final hasWrite = requested.whereType<FsWriteCap>().any(isGranted);
    final hasNet   = requested.whereType<NetOutCap>().any(isGranted);
    final hasProc  = requested.whereType<ProcSpawnCap>().any(isGranted);

    return _GrantedCaps(hasRead, hasWrite, hasNet, hasProc);
  }

  Future<IWritableFsContext?> createFsContext();
  Future<INetContext?> createNetContext(SandboxPolicy policy);
  Future<IProcContext?> createProcContext(SandboxPolicy policy);

  @override
  Future<void> suspend() async => status = SandboxStatus.suspended;

  @override
  Future<void> resume() async => status = SandboxStatus.ready;
}

final class _GrantedCaps {
  final bool hasRead;
  final bool hasWrite;
  final bool hasNet;
  final bool hasProc;
  _GrantedCaps(this.hasRead, this.hasWrite, this.hasNet, this.hasProc);
}
