import 'package:aq_schema/sandbox.dart';

/// Внутренний сервис Sandbox Plane.
///
/// Регистрирует живые ресурсы и закрывает их при dispose sandbox.
/// Порядок закрытия — обратный порядку регистрации (LIFO).
final class SandboxResourceManager {
  final List<IDisposable> _tracked = [];

  void track(IDisposable disposable) => _tracked.add(disposable);

  Future<void> disposeAll() async {
    for (final disposable in _tracked.reversed) {
      if (!disposable.isDisposed) await disposable.dispose();
    }
    _tracked.clear();
  }
}
