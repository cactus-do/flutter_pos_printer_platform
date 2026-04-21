import 'dart:async';
import 'dart:io';

/// Serializes access to network printers by IP:Port.
/// Only one operation (write, heartbeat, discovery probe) can use a given
/// device at a time. The socket is created fresh for each operation and
/// destroyed immediately when done, allowing multiple external devices to
/// share the same printer.
class _NetworkManager {
  static final _NetworkManager _instance = _NetworkManager._();
  _NetworkManager._();

  final Map<String, Completer<void>> _locks = {};

  String _key(String host, int port) => '$host:$port';

  Future<Socket> _acquire(String host, int port, {Duration? timeout}) async {
    final key = _key(host, port);

    // Queue behind any in-progress operation on this device
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    _locks[key] = Completer<void>();

    try {
      return await Socket.connect(host, port, timeout: timeout);
    } catch (e) {
      // Release the lock immediately so retries are not permanently blocked
      final lock = _locks.remove(key);
      if (lock != null && !lock.isCompleted) lock.complete();
      rethrow;
    }
  }

  void _release(String host, int port, Socket socket) {
    socket.destroy();
    final key = _key(host, port);
    final lock = _locks.remove(key);
    if (lock != null && !lock.isCompleted) lock.complete();
  }
}

mixin SocketConsumer {
  /// Acquires exclusive access to the device at [host]:[port], runs [action]
  /// with the socket, then releases access (even on error or timeout).
  Future<T> useSocket<T>(
    String host,
    int port,
    FutureOr<T> Function(Socket socket) action, {
    Duration? timeout,
  }) async {
    final socket = await _NetworkManager._instance._acquire(host, port, timeout: timeout);
    try {
      // Guard against the action hanging forever (e.g. socket.flush with a
      // full OS send buffer or a printer that stops ACKing mid-job).
      return await Future.value(action(socket)).timeout(const Duration(seconds: 15));
    } finally {
      _NetworkManager._instance._release(host, port, socket);
    }
  }
}