import 'dart:async';
import 'dart:io';

import 'package:flutter_pos_printer_platform_image_3/src/utils/network_analyzer.dart';

import '../../flutter_pos_printer_platform.dart';

/// This class is used to manage the socket connections with all the network devices
class NetworkManager {
  static final NetworkManager instance = NetworkManager._();
  NetworkManager._();

  final Map<String, Socket> _socketPool = {};
  final Map<String, Future<Socket>> _pendingConnections = {};
  final Map<String, Set<SocketConsumer>> _consumers = {};
  final Map<String, Completer<void>> _locks = {};

  String _getMapKey(String host, int port) {
    return '$host:$port';
  }

  Future<Socket> getSocket(SocketConsumer consumer, String host, int port, {Duration? timeout}) async {
    final key = _getMapKey(host, port);

    // Transparent Global Lock Queueing
    while (_locks.containsKey(key)) {
      await _locks[key]!.future;
    }
    _locks[key] = Completer<void>();

    try {
      return await _connect(consumer, host, port, timeout: timeout);
    } catch (e) {
      final lock = _locks.remove(key);
      if (lock != null && !lock.isCompleted) lock.complete();
      rethrow;
    }
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
        _removeFromPool(key);
      }).catchError((_) {
        _removeFromPool(key);
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

  void _removeFromPool(String key) {
    _socketPool.remove(key);
    _pendingConnections.remove(key);
    _consumers.remove(key);
    final lock = _locks.remove(key);
    if (lock != null && !lock.isCompleted) lock.complete();
  }

  /// Removes a consumer from the list of consumers for a given socket and closes the socket if no more consumers are using it
  void closeSocket(SocketConsumer consumer, String host, int port) {
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
  Future<Socket> getSocket(String host, int port, {Duration? timeout}) async {
    return NetworkManager.instance.getSocket(this, host, port, timeout: timeout);
  }

  void closeSocket(String host, int port) {
    NetworkManager.instance.closeSocket(this, host, port);
  }
}

class NetworkPrinterDiscoverer with SocketConsumer {
  static final NetworkPrinterDiscoverer instance = NetworkPrinterDiscoverer._();
  NetworkPrinterDiscoverer._();

  Future<PrinterInfo> getPrinterInfo({required String ipAddress, int port = 9100}) async {
    // Strategy A: ESC/POS (Port 9100)
    try {
      final socket = await getSocket(ipAddress, port, timeout: Duration(seconds: 2));
      // Send GS I n (Transmit Printer ID) - 68 = Serial Number (0x44)
      final serial = await _getEscPosData(socket, [0x1D, 0x49, 0x44]);
      // Send GS I n (Transmit Printer ID) - 67 = Model (0x43)
      final model = await _getEscPosData(socket, [0x1D, 0x49, 0x43]);

      return PrinterInfo(serialNumber: serial, model: model, manufacturer: 'Unknown');
    } catch (e) {
      print('ESC/POS Query failed: $e');
      return PrinterInfo();
    } finally {
      closeSocket(ipAddress, port);
    }
  }

  Future<String?> _getEscPosData(Socket socket, List<int> bytes) async {
    socket.add(bytes);

    final completer = Completer<String?>();
    final subscription = socket.asBroadcastStream().listen((data) {
      try {
        final filtered = data.where((b) => b >= 32 && b <= 126).toList();
        if (filtered.isNotEmpty) {
          final str = String.fromCharCodes(filtered);
          if (!completer.isCompleted) completer.complete(str);
        }
      } catch (e) {
        if (!completer.isCompleted) completer.complete(null);
      }
    });

    final result = await completer.future.timeout(Duration(seconds: 2), onTimeout: () => null);
    await subscription.cancel();
    return result;
  }

  Stream<PrinterDevice> discovery({
    String? ipAddress,
    int port = 9100,
    bool resolveIdentity = false,
  }) {
    print("Starting network discovery (TCP) on port $port (resolveIdentity: $resolveIdentity)");

    NetworkAnalyzer.instance.discover(port: port);
    final stream = NetworkAnalyzer.instance.discoveryStream;

    return stream.asyncMap((data) async {
      print("Found device at ${data.ip}");
      final device = PrinterDevice(name: "${data.ip}:$port", address: data.ip);

      if (resolveIdentity) {
        final info = await getPrinterInfo(ipAddress: data.ip, port: port);
        device.serialNumber = info.serialNumber;
        device.model = info.model;
        device.manufacturer = info.manufacturer;
      }

      return device;
    });
  }
}