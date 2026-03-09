import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'printer_transport.dart';
import 'package:flutter_pos_printer_platform_image_3/src/enums.dart';
import '../utils/network_analyzer.dart';
import '../models/printer_device.dart';
import '../printer_info.dart';

class TcpTransport extends PrinterTransport {
  final String ipAddress;
  final int port;
  final Duration timeout;

  final StreamController<PosPrinterConnectionState> _stateController = StreamController.broadcast();
  final StreamController<PrinterStatus> _statusController = StreamController.broadcast();
  Timer? _heartbeatTimer;

  TcpTransport({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  }) {
    _stateController.add(PosPrinterConnectionState.disconnected);
    _statusController.add(PrinterStatus.unknown);
  }

  // Global lock mechanism to prevent concurrent socket access to the same address (Static vs Instance)
  static final Map<String, Future<void>> _locks = {};
  
  static Future<T> synchronizedGlobal<T>(String address, int port, Future<T> Function() action) async {
    final key = "$address:$port";
    final previousLock = _locks[key] ?? Future.value();
    final completer = Completer<T>();
    _locks[key] = completer.future.then((_) => null).catchError((_) => null);
    
    await previousLock;
    try {
      final result = await action();
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    }
  }

  Future<T> _synchronizedLocal<T>(Future<T> Function() action) async {
    return synchronizedGlobal(ipAddress, port, action);
  }


  @override
  Stream<PosPrinterConnectionState> get state => _stateController.stream;

  @override
  Stream<PrinterStatus> get status => _statusController.stream;

  @override
  Future<bool> connect() async {
    return _synchronizedLocal(() async {
      try {
        _stateController.add(PosPrinterConnectionState.connecting);
        final socket = await Socket.connect(ipAddress, port, timeout: timeout);
        _stateController.add(PosPrinterConnectionState.connected);
        _statusController.add(PrinterStatus.good);

        socket.destroy();
        _startHeartbeat();
        return true;
      } catch (e) {
        _disconnectCleanup();
        return false;
      }
    });
  }

  void _startHeartbeat() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      await _synchronizedLocal(() async {
        // Send DLE EOT 4 (Real-time status transmission: Paper sensor)
        // 0x10 0x04 0x04
        try {
          final socket = await Socket.connect(ipAddress, port, timeout: timeout);
          socket.add(Uint8List.fromList([0x10, 0x04, 0x04]));
          await socket.flush();
          socket.destroy();
        } catch (e) {
          _disconnectCleanup();
        }
      });
    });
  }



  // void _parseStatus(Uint8List data) {
  //   if (data.isEmpty) return;
  //   // DLE EOT 4 response is 1 byte.
  //   // We might receive other data if we add read support later.
  //   // For now, assume single byte status if length is 1.
  //   for (final byte in data) {
  //     // Check for paper end
  //     // Bit 5 and 6 = 1 means Paper End.
  //     // 0x60 mask.
  //     // If (byte & 0x60) == 0x60 -> Paper Empty
  //     // If (byte & 0x0C) == 0x0C -> Paper Near End

  //     // Standard ESC/POS Status (n=4):
  //     // Bit 0: Fixed 0
  //     // Bit 1: Fixed 1
  //     // Bit 2,3: Paper roll near-end sensor: 00=Paper adequate, 11=Paper near end
  //     // Bit 4: Fixed 0
  //     // Bit 5,6: Paper roll end sensor: 00=Paper present, 11=Paper end
  //     // Bit 7: Fixed 0

  //     // So byte should look like 0xx0xxxx (binary)

  //     if ((byte & 0x60) == 0x60) {
  //       _statusController.add(PrinterStatus.paperOut);
  //     } else if ((byte & 0x0C) == 0x0C) {
  //       _statusController.add(PrinterStatus.paperLow);
  //     } else {
  //       _statusController.add(PrinterStatus.good);
  //     }
  //   }
  // }

  @override
  Future<bool> disconnect() async {
    await _disconnectCleanup();
    return true;
  }

  Future<void> _disconnectCleanup() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _stateController.add(PosPrinterConnectionState.disconnected);
    _statusController.add(PrinterStatus.unknown);
  }

  @override
  Future<bool> write(List<int> bytes) async {
    return _synchronizedLocal(() async {
      try {
        _startHeartbeat();
        final socket = await Socket.connect(ipAddress, port, timeout: timeout);
        socket.add(Uint8List.fromList(bytes));
        await socket.flush();
        socket.destroy();
        return true;
      } catch (e) {
        await _disconnectCleanup();
        return false;
      }
    });
  }



  /// Starts a scan for network printers.
  /// If [resolveIdentity] is true, it will attempt to fetch the serial number for each found printer.
  static Stream<PrinterDevice> discovery({
    String? ipAddress,
    int port = 9100,
    bool resolveIdentity = false,
  }) async* {
    print("Starting network discovery (TCP) on port $port (resolveIdentity: $resolveIdentity)");

    final stream = (await NetworkAnalyzer.discoverAllLocal(port: port)).asBroadcastStream();

    await for (var data in stream) {      
      if (data.exists) {
        print("Found device at ${data.ip}");
        var device = PrinterDevice(name: "${data.ip}:$port", address: data.ip);

        if (resolveIdentity) {
          final info = await getPrinterInfo(ipAddress: data.ip, port: port);
          device.serialNumber = info.serialNumber;
          device.model = info.model;
          device.manufacturer = info.manufacturer;
        }

        yield device;
      }
    }
    print("Network discovery finished.");
  }

  static Future<PrinterInfo> getPrinterInfo({required String ipAddress, int port = 9100}) async {
    return synchronizedGlobal(ipAddress, port, () async {

      Socket? socket;
      // Strategy A: ESC/POS (Port 9100)
      try {
        socket = await Socket.connect(ipAddress, port, timeout: Duration(seconds: 2));
        // Send GS I n (Transmit Printer ID) - 68 = Serial Number (0x44)
        final serial = await _getEscPosData(socket, [0x1D, 0x49, 0x44]);
        // Send GS I n (Transmit Printer ID) - 67 = Model (0x43)
        final model = await _getEscPosData(socket, [0x1D, 0x49, 0x43]);

        return PrinterInfo(serialNumber: serial, model: model, manufacturer: 'Unknown');
      } catch (e) {
        print('ESC/POS Query failed: $e');
        return PrinterInfo();
      } finally {
        socket?.destroy();
      }
    });
  }


  static Future<String?> _getEscPosData(Socket socket, List<int> bytes) async {
    socket.add(bytes);
    
    final completer = Completer<String?>();
    final subscription = socket.listen((data) {
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
}
