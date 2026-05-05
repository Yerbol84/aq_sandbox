// aq_sandbox/lib/src/provisioners/git_repo_provisioner.dart
//
// GitRepoProvisioner — git clone + build steps + кеш артефакта.
//
// Фаза 5: провизионирует git_repo Subject.
// 1. git clone (или pull если уже клонировано)
// 2. Выполняет buildSteps (docker build, npm install, etc.)
// 3. Кеширует артефакт по cacheKey

import 'dart:io';
import 'package:path/path.dart' as p;

/// Результат провизионирования.
final class ProvisionResult {
  final String artifactDir;
  final bool fromCache;
  final Duration elapsed;

  const ProvisionResult({
    required this.artifactDir,
    required this.fromCache,
    required this.elapsed,
  });
}

/// Провизионирует git репозиторий: clone + build + кеш.
///
/// Использование:
/// ```dart
/// final provisioner = GitRepoProvisioner(cacheDir: '/tmp/aq-cache');
/// final result = await provisioner.provision(
///   url: 'https://github.com/user/my-agent',
///   branch: 'main',
///   buildSteps: ['docker build -t my-agent .'],
///   cacheKey: 'my-agent-main',
/// );
/// ```
final class GitRepoProvisioner {
  final String cacheDir;

  /// Per-key lock: параллельные вызовы с одним ключом ждут первого.
  final Map<String, Future<ProvisionResult>> _locks = {};

  GitRepoProvisioner({required this.cacheDir});

  /// Провизионировать репозиторий.
  ///
  /// [url] — git URL репозитория.
  /// [branch] — ветка (default: main).
  /// [buildSteps] — команды сборки (выполняются в workDir).
  /// [cacheKey] — ключ кеша. Если null — кеш не используется.
  Future<ProvisionResult> provision({
    required String url,
    String branch = 'main',
    List<String> buildSteps = const [],
    String? cacheKey,
  }) {
    final lockKey = cacheKey ?? _urlToDir(url);
    // Если уже идёт провизионирование для этого ключа — ждём его результата.
    final existing = _locks[lockKey];
    if (existing != null) return existing;

    final future = _provision(url: url, branch: branch, buildSteps: buildSteps, cacheKey: cacheKey)
        .whenComplete(() => _locks.remove(lockKey));
    _locks[lockKey] = future;
    return future;
  }

  Future<ProvisionResult> _provision({
    required String url,
    String branch = 'main',
    List<String> buildSteps = const [],
    String? cacheKey,
  }) async {
    final start = DateTime.now();

    // Проверяем кеш
    if (cacheKey != null) {
      final cached = await _checkCache(cacheKey);
      if (cached != null) {
        return ProvisionResult(
          artifactDir: cached,
          fromCache: true,
          elapsed: DateTime.now().difference(start),
        );
      }
    }

    // Определяем директорию для клонирования
    final repoDir = cacheKey != null
        ? p.join(cacheDir, 'repos', cacheKey)
        : p.join(cacheDir, 'repos', _urlToDir(url));

    // Clone или pull
    await _cloneOrPull(url, branch, repoDir);

    // Build steps
    for (final step in buildSteps) {
      await _runStep(step, repoDir);
    }

    // Сохраняем в кеш
    if (cacheKey != null) {
      await _saveCache(cacheKey, repoDir);
    }

    return ProvisionResult(
      artifactDir: repoDir,
      fromCache: false,
      elapsed: DateTime.now().difference(start),
    );
  }

  /// Проверить наличие кеша. Возвращает путь или null.
  Future<String?> _checkCache(String cacheKey) async {
    final cacheMarker = p.join(cacheDir, 'cache', '$cacheKey.done');
    final artifactDir = p.join(cacheDir, 'repos', cacheKey);
    if (await File(cacheMarker).exists() && await Directory(artifactDir).exists()) {
      return artifactDir;
    }
    return null;
  }

  Future<void> _saveCache(String cacheKey, String artifactDir) async {
    final cacheMarker = p.join(cacheDir, 'cache', '$cacheKey.done');
    await Directory(p.dirname(cacheMarker)).create(recursive: true);
    await File(cacheMarker).writeAsString(DateTime.now().toIso8601String());
  }

  Future<void> _cloneOrPull(String url, String branch, String repoDir) async {
    final dir = Directory(repoDir);
    if (await dir.exists()) {
      // Pull если уже клонировано
      final result = await Process.run(
        'git', ['pull', 'origin', branch],
        workingDirectory: repoDir,
      );
      if (result.exitCode != 0) {
        throw GitProvisionException('git pull failed: ${result.stderr}');
      }
    } else {
      await dir.create(recursive: true);
      final result = await Process.run(
        'git', ['clone', '--branch', branch, '--depth', '1', url, repoDir],
      );
      if (result.exitCode != 0) {
        throw GitProvisionException('git clone failed: ${result.stderr}');
      }
    }
  }

  Future<void> _runStep(String step, String workDir) async {
    // Разбиваем команду на части (простой split по пробелам)
    final parts = step.split(' ').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return;

    final result = await Process.run(
      parts.first,
      parts.skip(1).toList(),
      workingDirectory: workDir,
    );
    if (result.exitCode != 0) {
      throw GitProvisionException('Build step "$step" failed: ${result.stderr}');
    }
  }

  /// Инвалидировать кеш для ключа.
  Future<void> invalidateCache(String cacheKey) async {
    final cacheMarker = p.join(cacheDir, 'cache', '$cacheKey.done');
    final f = File(cacheMarker);
    if (await f.exists()) await f.delete();
  }

  String _urlToDir(String url) =>
      url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

class GitProvisionException implements Exception {
  final String message;
  GitProvisionException(this.message);
  @override
  String toString() => 'GitProvisionException: $message';
}
