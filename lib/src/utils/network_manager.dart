import 'dart:async';
import 'dart:io';

/// This class is used to manage the socket connections with all the network devices
class _NetworkManager {
  static final _NetworkManager _instance = _NetworkManager._();
  _NetworkManager._();

  final Map<String, Socket> _socketPool = {};
  final Map<String, Future<Socket>> _pendingConnections = {};
  final Map<String, Set<SocketConsumer>> _consumers = {};
  final Map<String, Completer<void>> _locks = {};

  String _getMapKey(String host, int port) {
    return '$host:$port';
  }

  Future<Socket> _getSocket(SocketConsumer consumer, String host, int port, {Duration? timeout}) async {
    final key = _getMapKey(host, port);

    // Transparent Global Lock Queueing
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    _locks[key] = Completer<void>();

    return await _connect(consumer, host, port, timeout: timeout);
  }

  Future<Socket> _connect(SocketConsumer consumer, String host, int port, {Duration? timeout}) async {
    final key = _getMapKey(host, port);
    // Check if we already have it in the pool
    if (_socketPool.containsKey(key)) {
      _registerConsumer(consumer, host, port);
      return _socketPool[key]!;
    }

    // Check if there is a pending connection attempt
    if (_pendingConnections.containsKey(key)) {
      try {
        final socket = await _pendingConnections[key]!;
        _registerConsumer(consumer, host, port);
        return socket;
      } catch (e) {
        rethrow;
      }
    }

    // Start a new connection
    final completer = Completer<Socket>();
    _pendingConnections[key] = completer.future;

    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      _socketPool[key] = socket;
      _pendingConnections.remove(key);
      _registerConsumer(consumer, host, port);

      // Dead socket detection
      socket.done.then((_) {
        _removeFromPool(key, socket);
      }).catchError((_) {
        _removeFromPool(key, socket);
      });

      completer.complete(socket);
      return socket;
    } catch (e) {
      _pendingConnections.remove(key);
      print('Failed to connect to $host:$port due to $e');
      completer.completeError(e);
      rethrow;
    }
  }

  void _removeFromPool(String key, Socket expiredSocket) {
    if (_socketPool[key] == expiredSocket) {
      _socketPool.remove(key);
      _pendingConnections.remove(key);
      _consumers.remove(key);
      // NOTE: We absolutely do NOT clear _locks here. 
      // Locks belong to the active operation, not the socket. 
      // The operation's 'finally' block will close the lock.
    }
  }

  /// Removes a consumer from the list of consumers for a given socket and closes the socket if no more consumers are using it
  void _closeSocket(SocketConsumer consumer, String host, int port) {
    final key = _getMapKey(host, port);

    final lock = _locks.remove(key);
    if (lock != null && !lock.isCompleted) lock.complete();

    final consumers = _consumers[key];
    if (consumers != null) {
      consumers.remove(consumer);
      if (consumers.isEmpty) {
        _consumers.remove(key);
        final socket = _socketPool.remove(key);
        socket?.destroy();
      }
    }
  }

  /// Registers a consumer for a given socket
  void _registerConsumer(SocketConsumer consumer, String host, int port) {
    final key = _getMapKey(host, port);
    _consumers[key] ??= Set<SocketConsumer>();
    _consumers[key]?.add(consumer);
  }
}

mixin SocketConsumer {
  /// Executes the provided action with a network socket, guaranteeing the socket 
  /// is retrieved and safely closed using the global NetworkManager lock.
  Future<T> useSocket<T>(
    String host, 
    int port, 
    FutureOr<T> Function(Socket socket) action, 
    {Duration? timeout}
  ) async {
    try {
      final socket = await _NetworkManager._instance._getSocket(this, host, port, timeout: timeout);
      return await action(socket);
    } finally {
      _NetworkManager._instance._closeSocket(this, host, port);
    }
  }
}