import 'dart:async';
import 'package:flutter_pos_printer_platform_image_3/src/platform_interface/flutter_pos_printer_platform.dart';
import '../enums.dart'; // For USBStatus
import '../models/printer_device.dart';
import '../printer_info.dart';
import 'printer_transport.dart';

class UsbTransport extends PrinterTransport {
  final String? vendorId;
  final String? productId;
  final String? name;
  final String? address;

  UsbTransport({this.vendorId, this.productId, this.name, this.address});

  final _platform = FlutterPosPrinterPlatform.instance;

  @override
  Future<bool> connect() async {
    return await _platform.connect(
      name: name,
      vendorId: vendorId,
      productId: productId,
      address: address,
    );
  }

  @override
  Future<bool> disconnect() async {
    return await _platform.disconnect();
  }

  @override
  Future<bool> write(List<int> bytes) async {
    return await _platform.write(bytes);
  }

  @override
  Stream<PosPrinterConnectionState> get state {
    return _platform.state.map((status) {
      switch (status) {
        case USBStatus.connected:
          return PosPrinterConnectionState.connected;
        case USBStatus.connecting:
          return PosPrinterConnectionState.connecting;
        default:
          return PosPrinterConnectionState.disconnected;
      }
    });
  }

  @override
  Stream<PrinterStatus> get status {
    // USB status not fully implemented on platform side yet
    return _platform.state.map((status) {
      if (status == USBStatus.connected) {
        return PrinterStatus.good;
      } else {
        return PrinterStatus.unknown;
      }
    });
  }

  Future<List<int>?> read({int timeout = 2000}) async {
    return await _platform.read(timeout: timeout);
  }

  static Stream<PrinterDevice> discovery({bool resolveIdentity = true}) async* {
    final results = await FlutterPosPrinterPlatform.instance.getDeviceList();
    for (final device in results) {
      if (device is Map) {
        final vendorId = device['vendorId']?.toString();
        final productId = device['productId']?.toString();
        final address = device['name']?.toString();
        
        var mappedDevice = PrinterDevice(
          name: device['product'] ?? device['name'] ?? 'Unknown',
          vendorId: vendorId,
          productId: productId,
          address: address,
          manufacturer: device['manufacturer'],
          // Windows might map differently
        );

        if (resolveIdentity && vendorId != null && productId != null) {
          final info = await _getPrinterInfoInternal(vendorId: vendorId, productId: productId, address: address);
          if (info?.serialNumber != null) {
              mappedDevice.serialNumber = info?.serialNumber;
          }
          if (info?.model != null) {
              mappedDevice.model = info?.model;
          }
          if (info?.manufacturer != null && info?.manufacturer != 'Unknown') {
              mappedDevice.manufacturer = info?.manufacturer;
          }
        }

        yield mappedDevice;
      }
    }
  }

  static Future<PrinterInfo?> getPrinterInfo({
    required String vendorId,
    required String productId,
    required String address,
  }) {
    return _getPrinterInfoInternal(vendorId: vendorId, productId: productId, address: address);
  }

  static Future<PrinterInfo?> _getPrinterInfoInternal({
    String? vendorId,
    String? productId,
    String? address,
  }) async {
    final platform = FlutterPosPrinterPlatform.instance;
    final bool connected = await platform.connect(
      vendorId: vendorId,
      productId: productId,
      address: address,
    );
    
    if (!connected) return null;

    final List<int> accumulatedData = [];
    final subscription = platform.usbDataStream.listen((data) {
      accumulatedData.addAll(data);
    });

    try {
      // 1. Get Model
      await platform.write([0x1D, 0x49, 0x43]);
      final model = await _waitForResponse(accumulatedData);
      
      accumulatedData.clear();
      await Future.delayed(const Duration(milliseconds: 150));

      // 2. Get Serial
      await platform.write([0x1D, 0x49, 0x44]);
      final serial = await _waitForResponse(accumulatedData);
      
      return PrinterInfo(
        model: model,
        serialNumber: serial,
        manufacturer: 'Unknown',
      );
    } catch (e) {
      print('USB Printer Info Internal Query failed: $e');
      return null;
    } finally {
      await subscription.cancel();
      await platform.disconnect();
    }
  }

  /// Waits for data to arrive in the buffer and settles for a short window.
  static Future<String?> _waitForResponse(List<int> buffer, {int timeoutMs = 2000}) async {
    final startTime = DateTime.now();
    
    // Wait for first byte
    while (buffer.isEmpty) {
      if (DateTime.now().difference(startTime).inMilliseconds > timeoutMs) return null;
      await Future.delayed(const Duration(milliseconds: 50));
    }
    
    // Once data starts arriving, wait until it stops for at least 300ms (increased for stability)
    int lastSize = buffer.length;
    while (true) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (buffer.length == lastSize) break;
      lastSize = buffer.length;
      if (DateTime.now().difference(startTime).inMilliseconds > timeoutMs + 1000) break;
    }

    if (buffer.isNotEmpty) {
      final filteredList = buffer.where((b) => b >= 32 && b <= 126).toList();
      if (filteredList.isNotEmpty) {
        return String.fromCharCodes(filteredList);
      }
    }
    return null;
  }
}
