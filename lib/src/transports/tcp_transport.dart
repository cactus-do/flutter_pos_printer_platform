import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_pos_printer_platform_image_3/src/utils/network_manager.dart';

import 'printer_transport.dart';
import 'package:flutter_pos_printer_platform_image_3/src/enums.dart';
import '../models/printer_device.dart';
import '../printer_info.dart';

class TcpTransport extends PrinterTransport with SocketConsumer {
  final String ipAddress;
  final int port;
  final Duration timeout;

  final StreamController<PosPrinterConnectionState> _stateController = StreamController.broadcast();
  final StreamController<PrinterStatus> _statusController = StreamController.broadcast();

  late final _heartbeat = _Heartbeat(transport: this);

  TcpTransport({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  }) {
    _stateController.add(PosPrinterConnectionState.disconnected);
    _statusController.add(PrinterStatus.unknown);
  }

  @override
  Stream<PosPrinterConnectionState> get state => _stateController.stream;

  @override
  Stream<PrinterStatus> get status => _statusController.stream;

  @override
  Future<bool> connect() async {
    try {
      _stateController.add(PosPrinterConnectionState.connecting);
      await getSocket(ipAddress, port, timeout: timeout);
      _stateController.add(PosPrinterConnectionState.connected);
      _statusController.add(PrinterStatus.good);

      _heartbeat.start();
      return true;
    } catch (e) {
      _disconnectCleanup();
      return false;
    } finally {
      closeSocket(ipAddress, port);
    }
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
    _heartbeat.stop();
    _disconnectCleanup();
    // Demand-based connections are automatically closed by their consumers.
    // Unconditionally calling closeSocket here would corrupt active locks.
    return true;
  }

  void _disconnectCleanup() {
    _stateController.add(PosPrinterConnectionState.disconnected);
    _statusController.add(PrinterStatus.unknown);
  }

  @override
  Future<bool> write(List<int> bytes) async {
    int attempts = 0;
    const maxAttempts = 3;
    bool result = false;

    while (attempts < maxAttempts) {
      try {
        final socket = await getSocket(ipAddress, port, timeout: timeout);
        socket.add(Uint8List.fromList(bytes));
        await socket.flush();
        result = true;
        break;
      } catch (e) {
        attempts++;
        if (attempts >= maxAttempts) {
          _disconnectCleanup();
          break;
        }
        // Wait before next attempt (busy printer)
        await Future.delayed(const Duration(seconds: 2));
      } finally {
        closeSocket(ipAddress, port);
      }
    }
    return result;
  }

  /// Starts a scan for network printers.
  /// If [resolveIdentity] is true, it will attempt to fetch the serial number for each found printer.
  static Stream<PrinterDevice> discovery({String? ipAddress, int port = 9100, bool resolveIdentity = false}) {
    final instance = NetworkPrinterDiscoverer.instance;
    return instance.discovery(ipAddress: ipAddress, port: port, resolveIdentity: resolveIdentity);
  }

  static Future<PrinterInfo> getPrinterInfo({required String ipAddress, int port = 9100}) async {
    return NetworkPrinterDiscoverer.instance.getPrinterInfo(ipAddress: ipAddress, port: port);
  }
}

class _Heartbeat with SocketConsumer {
  final TcpTransport _transport;

  _Heartbeat({required TcpTransport transport}) : _transport = transport;

  Timer? _heartbeatTimer;

  void stop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void start() {
    stop();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final socket = await getSocket(_transport.ipAddress, _transport.port, timeout: _transport.timeout);
        socket.add(Uint8List.fromList([0x10, 0x04, 0x04]));
        await socket.flush();
      } catch (e) {
        stop();
        _transport._disconnectCleanup();
      } finally {
        closeSocket(_transport.ipAddress, _transport.port);
      }
    });
  }
}
