// aq_sandbox/lib/src/warm_pool.dart
//
// WarmPool — пул прогретых Docker контейнеров.
//
// Держит N готовых контейнеров чтобы избежать 5s cold start.
// Acquire: берёт готовый контейнер из пула (200ms вместо 5s).
// Release: возвращает контейнер в пул (или уничтожает если пул полон).
// Refill: автоматически пополняет пул до minSize в фоне.

import 'dart:async';
import 'dart:io';
import 'package:aq_schema/sandbox.dart';
import 'package:aq_schema/tools.dart';
import 'package:uuid/uuid.dart';
import 'handles/docker_sandbox_handle.dart';

/// Пул прогретых Docker контейнеров.
///
/// Использование:
/// ```dart
/// final pool = WarmPool(image: 'my-agent:latest', baseDir: '/tmp/aq', minSize: 2);
/// await pool.start();
///
/// final handle = await pool.acquire(sandboxId: uuid);
/// // ... использовать handle ...
/// await pool.release(handle); // вернуть в пул
///
/// await pool.dispose();
/// ```
final class WarmPool {
  final String image;
  final String baseDir;
  final int minSize;
  final int maxSize;
  final Map<String, String> extraEnv;

  final _pool = <DockerSandboxHandle>[];
  bool _running = false;
  Timer? _refillTimer;

  WarmPool({
    required this.image,
    required this.baseDir,
    this.minSize = 2,
    this.maxSize = 5,
    this.extraEnv = const {},
  });

  /// Запустить пул — прогреть minSize контейнеров.
  Future<void> start() async {
    _running = true;
    await _refill();
    _refillTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refill());
  }

  /// Взять контейнер из пула.
  ///
  /// Возвращает (handle, context, resources) — полный контекст как ISandboxProvider.create().
  /// Caller пишет файлы через context.fsWrite, не через shell exec.
  /// Если пул пуст — создаёт новый контейнер (cold start).
  Future<(DockerSandboxHandle, RunContext, SandboxResources)> acquire({
    required String sandboxId,
    SandboxPolicy? policy,
  }) async {
    final handle = _pool.isNotEmpty ? _pool.removeLast() : await _createWarmed(sandboxId);
    if (_pool.isNotEmpty) unawaited(_refill());

    final effectivePolicy = policy ?? SandboxPolicy.development();
    final (context, resources) = await handle.createContext(
      requestedCaps: [FsReadCap('**'), FsWriteCap('**')],
      policy: effectivePolicy,
      runId: const Uuid().v4(),
    );
    return (handle, context, resources);
  }

  /// Вернуть контейнер в пул или уничтожить если пул полон.
  /// [resources] — освобождаются всегда перед возвратом в пул.
  Future<void> release(DockerSandboxHandle handle, SandboxResources resources) async {
    await resources.dispose();
    if (_pool.length < maxSize && _running) {
      _pool.add(handle);
    } else {
      await handle.dispose(saveArtifacts: false);
    }
  }

  /// Остановить пул и уничтожить все контейнеры.
  Future<void> dispose() async {
    _running = false;
    _refillTimer?.cancel();
    for (final h in _pool) {
      await h.dispose(saveArtifacts: false);
    }
    _pool.clear();
  }

  int get poolSize => _pool.length;

  Future<void> _refill() async {
    if (!_running) return;
    while (_pool.length < minSize) {
      try {
        final id = const Uuid().v4();
        final handle = await _createWarmed(id);
        if (_running) {
          _pool.add(handle);
        } else {
          await handle.dispose(saveArtifacts: false);
          break;
        }
      } catch (_) {
        break; // Docker недоступен — не падаем
      }
    }
  }

  Future<DockerSandboxHandle> _createWarmed(String sandboxId) async {
    final workDir = '$baseDir/$sandboxId';
    await Directory(workDir).create(recursive: true);

    final handle = DockerSandboxHandle(
      sandboxId,
      workDir,
      image: image,
      extraEnv: extraEnv,
    );

    // Запускаем контейнер с sleep чтобы он оставался живым
    await handle.startContainer(command: ['sleep', 'infinity']);
    return handle;
  }
}
