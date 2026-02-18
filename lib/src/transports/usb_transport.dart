import 'package:flutter_pos_printer_platform_image_3/src/platform_interface/flutter_pos_printer_platform.dart';
import '../enums.dart'; // For USBStatus
import '../models/printer_device.dart';
import 'printer_transport.dart';

class UsbTransport extends PrinterTransport {
  final String? vendorId;
  final String? productId;
  final String? name;

  UsbTransport({this.vendorId, this.productId, this.name});

  final _platform = FlutterPosPrinterPlatform.instance;

  @override
  Future<bool> connect() async {
    return await _platform.connect(
      name: name,
      vendorId: vendorId,
      productId: productId,
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

  static Stream<PrinterDevice> discovery() async* {
    final results = await FlutterPosPrinterPlatform.instance.getDeviceList();
    for (final device in results) {
      if (device is Map) {
        yield PrinterDevice(
          name: device['product'] ?? device['name'] ?? 'Unknown',
          vendorId: device['vendorId']?.toString(),
          productId: device['productId']?.toString(),
          manufacturer: device['manufacturer'],
          // Windows might map differently
        );
      }
    }
  }
}
