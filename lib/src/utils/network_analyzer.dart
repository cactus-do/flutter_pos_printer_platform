import 'dart:async';
import 'package:flutter_pos_printer_platform_image_3/src/utils/network_manager.dart';
import 'dart:io';

class NetworkAddress {
  final String ip;
  final bool exists;
  NetworkAddress(this.ip, this.exists);
}

class NetworkAnalyzer with SocketConsumer {
  static final NetworkAnalyzer instance = NetworkAnalyzer._();
  NetworkAnalyzer._();

  List<Future<NetworkAddress>> _discover(
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

    return futures;
  }

  Future<NetworkAddress> _checkConnection(
    String ip,
    int port,
    Duration timeout,
  ) async {
    try {
      await getSocket(ip, port);
      return NetworkAddress(ip, true);
    } catch (e) {
      return NetworkAddress(ip, false);
    } finally {
      closeSocket(ip, port);
    }
  }
  
  Stream<NetworkAddress> discover({int port = 9100}) {
    return _discoverAll(port).asStream().expand((e) => e).where((e) => e.exists);
  }

  // Returns all ip addresses that needs to be checked for connection of all network interfaces
  Future<List<NetworkAddress>> _discoverAll(int port) async {
    // get networks from all network interfaces
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
    // map to subnet and remove duplicates
    final ns = ifs.expand((e) => e.addresses.map((ip) => ip.address.substring(0, ip.address.lastIndexOf('.')))).toSet();
    // discover printers in each subnet
    final discovery = ns.expand((add) => _discover(add, port, timeout: Duration(milliseconds: 500))).toList();
    return Future.wait(discovery);
  }
}
