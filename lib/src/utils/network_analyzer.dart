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

  bool _isDiscovering = false;

  /// Scans the local network for devices listening on [port].
  /// Returns a stream that emits each found [NetworkAddress] and closes when done.
  Stream<NetworkAddress> discover({int port = 9100}) async* {
    if (_isDiscovering) return;

    _isDiscovering = true;
    try {
      final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      final subnets = ifs
          .expand((e) => e.addresses.map((ip) => ip.address.substring(0, ip.address.lastIndexOf('.'))))
          .toSet();

      final ips = <String>[];
      for (final subnet in subnets) {
        for (int i = 1; i < 256; i++) {
          ips.add('$subnet.$i');
        }
      }

      yield* _scanIps(ips, port);
    } finally {
      _isDiscovering = false;
    }
  }

  Stream<NetworkAddress> _scanIps(List<String> ips, int port) async* {
    const batchSize = 30;

    for (int i = 0; i < ips.length; i += batchSize) {
      final batch = ips.skip(i).take(batchSize).toList();

      final results = await Future.wait(
        batch.map((ip) => _checkConnection(ip, port, const Duration(milliseconds: 500))),
      );

      for (final result in results) {
        if (result.exists) yield result;
      }
    }
  }

  Future<NetworkAddress> _checkConnection(String ip, int port, Duration timeout) async {
    try {
      return await useSocket(ip, port, timeout: timeout, (socket) async {
        return NetworkAddress(ip, true);
      });
    } catch (_) {
      return NetworkAddress(ip, false);
    }
  }
}
