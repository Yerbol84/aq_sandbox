// aq_sandbox/lib/src/contexts/simple_proc_context.dart

import 'dart:io';
import 'package:aq_schema/sandbox.dart';

final class SimpleProcContext implements IProcContext {
  final Set<String> _allowedBinaries;
  final String _workDir;
  bool _disposed = false;

  SimpleProcContext(this._allowedBinaries, this._workDir);

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> dispose() async => _disposed = true;

  @override
  Future<ProcResult> run(
    String binary,
    List<String> args, {
    String? workingSubDir,
    Duration? timeout,
    Map<String, String>? extraEnv,
  }) async {
    if (!_allowedBinaries.contains(binary)) {
      throw BinaryNotAllowedError(binary);
    }

    final workDir = workingSubDir != null ? '$_workDir/$workingSubDir' : _workDir;
    final result = await Process.run(
      binary,
      args,
      workingDirectory: workDir,
      environment: extraEnv,
    );

    return ProcResult(result.exitCode, result.stdout.toString(), result.stderr.toString());
  }
}

final class BinaryNotAllowedError implements Exception {
  final String binary;
  BinaryNotAllowedError(this.binary);
  @override
  String toString() => 'Binary not allowed: $binary';
}
