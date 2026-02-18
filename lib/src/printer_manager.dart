import 'dart:io';
import 'package:flutter_pos_printer_platform_image_3/src/enums.dart';
import 'package:flutter_pos_printer_platform_image_3/src/models/printer_device.dart';
import 'package:flutter_pos_printer_platform_image_3/src/models/printer_input.dart';
import 'package:flutter_pos_printer_platform_image_3/src/printer_info.dart';
import 'package:flutter_pos_printer_platform_image_3/src/transports/tcp_transport.dart';
import 'package:flutter_pos_printer_platform_image_3/src/transports/usb_transport.dart';
// Export enums so they are available to users of PrinterManager
export 'enums.dart';
export 'models/printer_input.dart';

class PrinterManager {
  // We keep a single USB transport instance as it wraps the platform channel (singleton)
  UsbTransport _usbTransport = UsbTransport();
  TcpTransport? _tcpTransport;

  PrinterManager._();

  static PrinterManager _instance = PrinterManager._();

  static PrinterManager get instance => _instance;

  Stream<PrinterDevice> discovery({required PrinterType type, TcpPrinterInput? model}) {
    if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return UsbTransport.discovery();
    } else {
      return TcpTransport.discovery(ipAddress: model?.ipAddress, port: model?.port ?? 9100);
    }
  }

  Future<bool> connect({required PrinterType type, required BasePrinterInput model}) async {
    if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      try {
        if (model is UsbPrinterInput) {
          _usbTransport = UsbTransport(
            vendorId: model.vendorId,
            productId: model.productId,
            name: model.name,
          );
        }
        return await _usbTransport.connect();
      } catch (e) {
        throw Exception('model must be type of UsbPrinterInput');
      }
    } else {
      try {
        var input = model as TcpPrinterInput;
        _tcpTransport = TcpTransport(
          ipAddress: input.ipAddress,
          port: input.port,
          timeout: input.timeout,
        );
        return await _tcpTransport!.connect();
      } catch (e) {
        throw Exception('model must be type of TcpPrinterInput');
      }
    }
  }

  Future<bool> disconnect({required PrinterType type, int? delayMs}) async {
    if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      final res = await _usbTransport.disconnect();
      if (delayMs != null) await Future.delayed(Duration(milliseconds: delayMs));
      return res;
    } else {
      return await _tcpTransport?.disconnect() ?? true;
    }
  }

  Future<bool> send({required PrinterType type, required List<int> bytes}) async {
    if (type == PrinterType.usb && (Platform.isAndroid || Platform.isWindows)) {
      return await _usbTransport.send(bytes);
    } else {
      if (_tcpTransport == null) return false;
      return await _tcpTransport!.send(bytes);
    }
  }

  Future<PrinterInfo> getPrinterInfo({required PrinterType type, BasePrinterInput? model}) async {
    if (type == PrinterType.network && model is TcpPrinterInput) {
      return await TcpTransport.getPrinterInfo(ipAddress: model.ipAddress, port: model.port);
    }
    return PrinterInfo();
  }

  Stream<USBStatus> get stateUSB => _usbTransport.state.map((s) {
        if (s == PosPrinterConnectionState.connected) return USBStatus.connected;
        if (s == PosPrinterConnectionState.connecting) return USBStatus.connecting;
        return USBStatus.none;
      });

  USBStatus get currentStatusUSB {
    // We don't have a sync getter on transport, but mostly for UI.
    // Return none for now, or we'd need to cache state in Manager.
    return USBStatus.none;
  }
}
