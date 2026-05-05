// aq_sandbox/lib/src/contexts/simple_net_context.dart

import 'dart:convert';
import 'dart:io';
import 'package:aq_schema/sandbox.dart';

final class SimpleNetContext implements INetContext {
  final Set<String> _allowedHosts;
  bool _disposed = false;

  SimpleNetContext(this._allowedHosts);

  @override
  bool get isDisposed => _disposed;

  @override
  Future<void> dispose() async => _disposed = true;

  void _checkHost(String url) {
    final uri = Uri.parse(url);
    final host = uri.host;
    
    if (!_allowedHosts.contains('*') && !_allowedHosts.contains(host)) {
      throw HostNotAllowedError(host);
    }
  }

  HttpClient _makeClient(String url) {
    final client = HttpClient();
    // Bypass system proxy для loopback и host.docker.internal (Ollama, OmniRoute)
    final host = Uri.parse(url).host;
    if (host == 'localhost' || host == '127.0.0.1' || host == '::1' ||
        host == 'host.docker.internal') {
      client.findProxy = (_) => 'DIRECT';
    }
    return client;
  }

  /// Добавляет X-Forwarded-For: 127.0.0.1 для запросов к localhost.
  ///
  /// OmniRoute проверяет IP клиента по ключу. Dart HttpClient идёт с
  /// container IP (172.x.x.x), а не loopback — добавляем заголовок явно.
  Map<String, String> _addLoopbackHeader(String url, Map<String, String>? headers) {
    final host = Uri.parse(url).host;
    if (host == 'localhost' || host == '127.0.0.1') {
      return {...?headers, 'X-Forwarded-For': '127.0.0.1'};
    }
    return headers ?? {};
  }

  @override
  Future<HttpResponse> get(String url, {Map<String, String>? headers}) async {
    _checkHost(url);
    final client = _makeClient(url);
    final effectiveHeaders = _addLoopbackHeader(url, headers);
    try {
      final request = await client.getUrl(Uri.parse(url));
      effectiveHeaders.forEach((k, v) => request.headers.add(k, v));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return HttpResponse(response.statusCode, responseHeaders, body);
    } finally {
      client.close();
    }
  }

  @override
  Future<HttpResponse> post(String url, {Object? body, Map<String, String>? headers}) async {
    _checkHost(url);
    final client = _makeClient(url);
    final effectiveHeaders = _addLoopbackHeader(url, headers);
    try {
      final request = await client.postUrl(Uri.parse(url));
      effectiveHeaders.forEach((k, v) => request.headers.add(k, v));
      if (body != null) {
        request.write(body is String ? body : jsonEncode(body));
      }
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });
      return HttpResponse(response.statusCode, responseHeaders, responseBody);
    } finally {
      client.close();
    }
  }

  @override
  Stream<String> postStream(String url, {Object? body, Map<String, String>? headers}) async* {
    _checkHost(url);
    final client = _makeClient(url);
    final effectiveHeaders = _addLoopbackHeader(url, headers);
    try {
      final request = await client.postUrl(Uri.parse(url));
      effectiveHeaders.forEach((k, v) => request.headers.add(k, v));
      if (body != null) {
        request.write(body is String ? body : jsonEncode(body));
      }
      final response = await request.close();
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        yield line;
      }
    } finally {
      client.close();
    }
  }
}

final class HostNotAllowedError implements Exception {
  final String host;
  HostNotAllowedError(this.host);
  @override
  String toString() => 'Host not allowed: $host';
}
