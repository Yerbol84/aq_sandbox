// aq_sandbox/lib/src/docker/docker_client.dart
//
// P-09: HTTP клиент к Docker Engine API через Unix socket.
// Заменяет Process.run('docker', ...) — structured errors, нет shell injection.
//
// Docker API docs: https://docs.docker.com/engine/api/v1.43/

import 'dart:convert';
import 'dart:io';

/// Тонкий клиент к Docker Engine API.
///
/// Использует Unix socket /var/run/docker.sock напрямую.
/// Все методы бросают [DockerApiException] при ошибке.
final class DockerClient {
  static const String _apiVersion = 'v1.43';
  final String socketPath;

  DockerClient({this.socketPath = '/var/run/docker.sock'});

  /// Запустить контейнер. Возвращает container ID.
  Future<String> containerCreate({
    required String image,
    required String name,
    List<String> binds = const [],
    String? workingDir,
    Map<String, String> env = const {},
    List<String> cmd = const [],
    int? stopTimeout,
  }) async {
    final body = {
      'Image': image,
      'WorkingDir': workingDir,
      'Cmd': cmd.isEmpty ? null : cmd,
      'Env': env.entries.map((e) => '${e.key}=${e.value}').toList(),
      'StopTimeout': stopTimeout,
      'HostConfig': {
        'Binds': binds,
      },
    }..removeWhere((_, v) => v == null);

    final response = await _post(
      '/$_apiVersion/containers/create?name=${Uri.encodeComponent(name)}',
      body,
    );
    return response['Id'] as String;
  }

  /// Запустить созданный контейнер.
  Future<void> containerStart(String containerId) async {
    await _postRaw('/$_apiVersion/containers/$containerId/start', null,
        expectedStatus: 204);
  }

  /// Выполнить команду в контейнере. Возвращает stdout.
  Future<String> containerExec(String containerId, List<String> cmd) async {
    // 1. Создать exec instance
    final exec = await _post(
      '/$_apiVersion/containers/$containerId/exec',
      {
        'AttachStdout': true,
        'AttachStderr': true,
        'Cmd': cmd,
      },
    );
    final execId = exec['Id'] as String;

    // 2. Запустить exec и получить вывод
    final raw = await _postRawBytes(
      '/$_apiVersion/exec/$execId/start',
      {'Detach': false, 'Tty': false},
      expectedStatus: 200,
    );

    // 3. Демультиплексировать Docker stream format:
    // [stream_type(1)] [0,0,0(3)] [size(4 big-endian)] [payload(size)]
    // stream_type: 1=stdout, 2=stderr
    return _demultiplex(raw);
  }

  /// Демультиплексирует Docker attach stream, возвращает только stdout.
  static String _demultiplex(List<int> bytes) {
    final buf = StringBuffer();
    var i = 0;
    while (i + 8 <= bytes.length) {
      final streamType = bytes[i];       // 1=stdout, 2=stderr
      final size = (bytes[i + 4] << 24) |
                   (bytes[i + 5] << 16) |
                   (bytes[i + 6] << 8)  |
                    bytes[i + 7];
      i += 8;
      if (i + size > bytes.length) break;
      if (streamType == 1) {             // только stdout
        buf.write(utf8.decode(bytes.sublist(i, i + size)));
      }
      i += size;
    }
    return buf.toString();
  }

  /// Приостановить контейнер.
  Future<void> containerPause(String containerId) async {
    await _postRaw('/$_apiVersion/containers/$containerId/pause', null,
        expectedStatus: 204);
  }

  /// Возобновить контейнер.
  Future<void> containerUnpause(String containerId) async {
    await _postRaw('/$_apiVersion/containers/$containerId/unpause', null,
        expectedStatus: 204);
  }

  /// Удалить контейнер (force=true — даже если запущен).
  Future<void> containerRemove(String containerId) async {
    await _deleteRaw(
        '/$_apiVersion/containers/$containerId?force=true',
        expectedStatus: 204);
  }

  // ── HTTP helpers ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic>? body) async {
    final raw = await _postRaw(path, body, expectedStatus: 201);
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<String> _postRaw(
    String path,
    Map<String, dynamic>? body, {
    required int expectedStatus,
  }) async {
    final bytes = await _postRawBytes(path, body, expectedStatus: expectedStatus);
    return utf8.decode(bytes);
  }

  Future<List<int>> _postRawBytes(
    String path,
    Map<String, dynamic>? body, {
    required int expectedStatus,
  }) async {
    final client = HttpClient();
    try {
      client.connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
          );

      final request = await client.postUrl(Uri.parse('http://localhost$path'));
      request.headers.set('Content-Type', 'application/json');
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));

      if (response.statusCode != expectedStatus) {
        throw DockerApiException(path, response.statusCode, utf8.decode(bytes));
      }
      return bytes;
    } finally {
      client.close();
    }
  }

  Future<void> _deleteRaw(String path, {required int expectedStatus}) async {
    final client = HttpClient();
    try {
      client.connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
          );

      final request = await client.deleteUrl(
        Uri.parse('http://localhost$path'),
      );
      final response = await request.close();
      await response.drain<void>();

      if (response.statusCode != expectedStatus) {
        throw DockerApiException(path, response.statusCode, '');
      }
    } finally {
      client.close();
    }
  }
}

class DockerApiException implements Exception {
  final String endpoint;
  final int statusCode;
  final String body;

  DockerApiException(this.endpoint, this.statusCode, this.body);

  @override
  String toString() =>
      'DockerApiException: $endpoint → HTTP $statusCode: $body';
}
