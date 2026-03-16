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

  final _discoveryController = StreamController<NetworkAddress>.broadcast();
  Stream<NetworkAddress> get discoveryStream => _discoveryController.stream;

  bool _isDiscovering = false;

  void _discover(
    String subnet,
    int port, {
    Duration timeout = const Duration(milliseconds: 400),
  }) {
    if (port < 1 || port > 65535) {
      throw 'Incorrect port';
    }

    for (int i = 1; i < 256; ++i) {
      final host = '$subnet.$i';
      _checkConnection(host, port, timeout).then((value) {
        if (!value.exists) return;
        _discoveryController.add(value);
      });
    }
    return;
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

  void discover({int port = 9100}) async {
    if (_isDiscovering) return;
    _isDiscovering = true;
    await _discoverAll(port);
    _isDiscovering = false;
  }

  // Returns all ip addresses that needs to be checked for connection of all network interfaces
  Future<void> _discoverAll(int port) async {
    // get networks from all network interfaces
    final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: false);
    // map to subnet and remove duplicates
    final ns = ifs.expand((e) => e.addresses.map((ip) => ip.address.substring(0, ip.address.lastIndexOf('.')))).toSet();
    // discover printers in each subnet
    for (final n in ns) {
      _discover(n, port, timeout: Duration(milliseconds: 500));
    }
    return;
  }
}
