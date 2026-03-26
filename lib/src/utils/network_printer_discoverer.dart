import 'dart:async';
import 'dart:io';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform.dart';
import 'package:flutter_pos_printer_platform_image_3/src/utils/network_analyzer.dart';
import 'package:flutter_pos_printer_platform_image_3/src/utils/network_manager.dart';

class NetworkPrinterDiscoverer with SocketConsumer {
  static final NetworkPrinterDiscoverer instance = NetworkPrinterDiscoverer._();
  NetworkPrinterDiscoverer._();

  Future<PrinterInfo> getPrinterInfo({required String ipAddress, int port = 9100}) async {
    // Strategy A: ESC/POS (Port 9100)
    try {
      return await useSocket(ipAddress, port, timeout: const Duration(seconds: 2), (socket) async {
        // Send GS I n (Transmit Printer ID) - 68 = Serial Number (0x44)
        final serial = await _getEscPosData(socket, [0x1D, 0x49, 0x44]);
        // Send GS I n (Transmit Printer ID) - 67 = Model (0x43)
        final model = await _getEscPosData(socket, [0x1D, 0x49, 0x43]);

        return PrinterInfo(serialNumber: serial, model: model, manufacturer: 'Unknown');
      });
    } catch (e) {
      print('ESC/POS Query failed: $e');
      return PrinterInfo();
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