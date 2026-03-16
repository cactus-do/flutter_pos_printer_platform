import 'dart:async';
import 'dart:io';
import 'package:flutter_pos_printer_platform_image_3/src/utils/network_manager.dart';

class NetworkAddress {
  final String ip;
  final bool exists;
  NetworkAddress(this.ip, this.exists);
}

class NetworkAnalyzer with SocketConsumer {
  static final NetworkAnalyzer instance = NetworkAnalyzer._();
  NetworkAnalyzer._();

  StreamController<NetworkAddress> _discoveryController = StreamController<NetworkAddress>.broadcast();

  Stream<NetworkAddress> get discoveryStream => _discoveryController.stream;

  bool _isDiscovering = false;

  Future<void> discover({int port = 9100}) async {
    if (_isDiscovering) return;

    _isDiscovering = true;
    _discoveryController = StreamController<NetworkAddress>.broadcast();

    await _discoverAll(port);

    await _discoveryController.close();
    _isDiscovering = false;
  }

  Future<void> _discoverAll(int port) async {
    final ifs = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    final subnets =
        ifs.expand((e) => e.addresses.map((ip) => ip.address.substring(0, ip.address.lastIndexOf('.')))).toSet();

    final ips = <String>[];

    for (final subnet in subnets) {
      for (int i = 1; i < 256; i++) {
        ips.add('$subnet.$i');
      }
    }

    await _scanIps(ips, port);
  }

  Future<void> _scanIps(List<String> ips, int port) async {
    const batchSize = 30;

    for (int i = 0; i < ips.length; i += batchSize) {
      final batch = ips.skip(i).take(batchSize);

      await Future.wait(
        batch.map((ip) async {
          final result = await _checkConnection(
            ip,
            port,
            const Duration(milliseconds: 500),
          );

          if (result.exists) {
            _discoveryController.add(result);
          }
        }),
      );
    }
  }

  Future<NetworkAddress> _checkConnection(
    String ip,
    int port,
    Duration timeout,
  ) async {
    try {
      await getSocket(ip, port, timeout: timeout);
      return NetworkAddress(ip, true);
    } catch (_) {
      return NetworkAddress(ip, false);
    } finally {
      closeSocket(ip, port);
    }
  }
}
