import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_snmp/dart_snmp.dart';

import 'package:flutter_pos_printer_platform_image_3/src/models/printer_device.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'package:flutter_pos_printer_platform_image_3/discovery.dart';
import 'package:flutter_pos_printer_platform_image_3/printer.dart';
import 'package:flutter_pos_printer_platform_image_3/src/printer_info.dart';
import 'package:ping_discover_network_forked/ping_discover_network_forked.dart';

class TcpPrinterInput extends BasePrinterInput {
  final String ipAddress;
  final int port;
  final Duration timeout;
  TcpPrinterInput({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });
}

class TcpPrinterInfo {
  String address;
  TcpPrinterInfo({
    required this.address,
  });
}

class TcpPrinterConnector implements PrinterConnector<TcpPrinterInput> {
  TcpPrinterConnector._();
  static TcpPrinterConnector _instance = TcpPrinterConnector._();

  static TcpPrinterConnector get instance => _instance;

  TcpPrinterConnector();
  Socket? _socket;
  final StreamController<List<int>> _readController = StreamController.broadcast();

  @override
  Stream<List<int>> get onRead => _readController.stream;

  static Future<List<PrinterDiscovered<TcpPrinterInfo>>> discoverPrinters({String? ipAddress, int? port, Duration? timeOut}) async {
    final List<PrinterDiscovered<TcpPrinterInfo>> result = [];
    final defaultPort = port ?? 9100;

    String? deviceIp;
    if (Platform.isAndroid || Platform.isIOS) {
      deviceIp = await NetworkInfo().getWifiIP();
    } else if (ipAddress != null) deviceIp = ipAddress;
    if (deviceIp == null) return result;

    final String subnet = deviceIp.substring(0, deviceIp.lastIndexOf('.'));
    // final List<String> ips = List.generate(255, (index) => '$subnet.$index');

    final stream = NetworkAnalyzer.discover2(
      subnet,
      defaultPort,
      timeout: timeOut ?? Duration(milliseconds: 4000),
    );

    await for (var addr in stream) {
      if (addr.exists) {
        result.add(PrinterDiscovered<TcpPrinterInfo>(name: "${addr.ip}:$defaultPort", detail: TcpPrinterInfo(address: addr.ip)));
      }
    }

    return result;
  }

  /// Starts a scan for network printers.
  Stream<PrinterDevice> discovery({TcpPrinterInput? model}) async* {
    final defaultPort = model?.port ?? 9100;

    print("Starting network discovery (TCP) on port $defaultPort");

    String? deviceIp;
    if (Platform.isAndroid || Platform.isIOS) {
      deviceIp = await NetworkInfo().getWifiIP();
      print("Device IP obtained: $deviceIp");
    } else if (model?.ipAddress != null) {
      deviceIp = model!.ipAddress;
    } else {
      print("No IP address found for discovery.");
      return;
    }

    if (deviceIp == null) {
      print("Device IP is null, aborting discovery.");
      return;
    }

    final String subnet = deviceIp.substring(0, deviceIp.lastIndexOf('.'));
    print("Scanning subnet: $subnet");

    final stream = NetworkAnalyzer.discover2(subnet, defaultPort);

    await for (var data in stream.map((message) => message)) {
      if (data.exists) {
        print("Found device at ${data.ip}");
        yield PrinterDevice(name: "${data.ip}:$defaultPort", address: data.ip);
      }
    }
    print("Network discovery finished.");
  }

  Future<PrinterInfo> getPrinterInfo(TcpPrinterInput model) async {
    PrinterInfo info = PrinterInfo();
    // Strategy A: ESC/POS (Port 9100)
    try {
      final socket = await Socket.connect(model.ipAddress, model.port, timeout: model.timeout);

      // Send GS I n (Transmit Printer ID) - 68 = Serial Number (0x44)
      socket.add([0x1D, 0x49, 0x44]);

      // Complete command list to fetch: 67 (Model), 65 (Firmware), 66 (Manufacturer)
      // For now focusing on Serial Number as primary goal

      // Use a completer to wait for response
      final completer = Completer<String?>();
      final subscription = socket.listen((data) {
        // Filter nulls and spaces
        try {
          // Typical response: [Header][Data][NUL]
          // Header might be 0x5F, or just raw data.
          // We just look for printable characters.
          final filtered = data.where((b) => b >= 32 && b <= 126).toList();
          if (filtered.isNotEmpty) {
            final str = String.fromCharCodes(filtered);
            if (!completer.isCompleted) completer.complete(str);
          }
        } catch (e) {
          if (!completer.isCompleted) completer.complete(null);
        }
      });

      final serial = await completer.future.timeout(Duration(seconds: 2), onTimeout: () => null);
      await subscription.cancel();
      socket.destroy();

      if (serial != null && serial.isNotEmpty) {
        return PrinterInfo(serialNumber: serial, model: 'Unknown', manufacturer: 'Unknown');
      }
    } catch (e) {
      print('ESC/POS Query failed: $e');
    }

    // Strategy B: SNMP (Fallback)
    try {
      final target = InternetAddress(model.ipAddress);
      final session = await Snmp.createSession(target);
      // OID for prtGeneralSerialNumber: 1.3.6.1.2.1.43.5.1.1.17.1
      final oid = Oid.fromString('1.3.6.1.2.1.43.5.1.1.17.1');
      final message = await session.get(oid);

      if (message.pdu.varbinds.isNotEmpty) {
        final serial = message.pdu.varbinds.first.value.toString();
        if (serial.isNotEmpty) {
          return PrinterInfo(
            serialNumber: serial,
            model: 'Unknown',
            manufacturer: 'Unknown',
          );
        }
      }
      session.close();
    } catch (e) {
      print('SNMP Query failed: $e');
    }

    return info;
  }

  @override
  Future<bool> send(List<int> bytes) async {
    try {
      if (_socket == null) return false;
      _socket!.add(Uint8List.fromList(bytes));
      await _socket!.flush();
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<bool> connect(TcpPrinterInput model) async {
    try {
      _socket = await Socket.connect(model.ipAddress, model.port, timeout: model.timeout);
      return true;
    } catch (e) {
      print(e);
      return false;
    }
  }

  /// [delayMs]: milliseconds to wait after closing the socket
  @override
  Future<bool> disconnect({int? delayMs}) async {
    try {
      _socket?.destroy();
      _socket = null;
      if (delayMs != null) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
