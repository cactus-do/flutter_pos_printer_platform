import 'dart:async' show Stream;
import 'package:async/async.dart' show StreamGroup;
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
  }) {
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

    return Stream.fromFutures(futures);
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

  /// Returns a list of streams for each existing network interface
  static Future<Stream<NetworkAddress>> discoverAllLocal({int port = 9100}) async {
    final streams = await _getAllLocalNetworks().then((address) =>
        address.map((address) => _getNetworkStream(address, port)).whereType<Stream<NetworkAddress>>().toList());
    return StreamGroup.merge(streams);
  }

  // Returns all ip addresses that needs to be checked for connection of all network interfaces
  static Future<List<String>> _getAllLocalNetworks() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: true);
    return interfaces.expand((e) => e.addresses.map((element) => element.address)).toList();
  }

  static Stream<NetworkAddress>? _getNetworkStream(String address, int port) {
    Stream<NetworkAddress>? stream;
    try {
      final subnet = address.substring(0, address.lastIndexOf('.'));
      // internally this method opens a socket with each ip address to test if there is connection
      stream = discover(subnet, port, timeout: const Duration(milliseconds: 500));
    } catch (error) {
      print('Error at NetworkScanner._getSubnetStream: $error');
    }
    return stream;
  }
}
