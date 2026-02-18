import 'dart:async';
import 'dart:io';

class NetworkAddress {
  final String ip;
  final bool exists;
  NetworkAddress(this.ip, this.exists);
}

class NetworkAnalyzer {
  static Stream<NetworkAddress> discover(
    String subnet,
    int port, {
    Duration timeout = const Duration(milliseconds: 400),
  }) async* {
    if (port < 1 || port > 65535) {
      throw 'Incorrect port';
    }
    // Subnet should be "192.168.1"

    // Create a list of futures to scan concurrently
    final List<Future<NetworkAddress>> futures = [];

    for (int i = 1; i < 256; ++i) {
      final host = '$subnet.$i';
      futures.add(_checkConnection(host, port, timeout));
    }

    // Process results as they complete? Or wait for all?
    // Streaming is better for UI.
    // However, future iteration order is not guaranteed.
    // A simple way is to yield them as they complete.

    final stream = Stream.fromFutures(futures);
    await for (final addr in stream) {
      yield addr;
    }
  }

  static Future<NetworkAddress> _checkConnection(
    String ip,
    int port,
    Duration timeout,
  ) async {
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.destroy();
      return NetworkAddress(ip, true);
    } catch (e) {
      return NetworkAddress(ip, false);
    }
  }
}
