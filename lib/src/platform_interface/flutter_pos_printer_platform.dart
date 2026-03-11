import 'package:flutter_pos_printer_platform_image_3/src/models/events.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'method_channel_flutter_pos_printer.dart';

abstract class FlutterPosPrinterPlatform extends PlatformInterface {
  /// Constructs a FlutterPosPrinterPlatform.
  FlutterPosPrinterPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterPosPrinterPlatform _instance = MethodChannelFlutterPosPrinter();

  /// The default instance of [FlutterPosPrinterPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterPosPrinter].
  static FlutterPosPrinterPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterPosPrinterPlatform] when
  /// they register themselves.
  static set instance(FlutterPosPrinterPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Discover available USB devices.
  Future<List<dynamic>> getDeviceList() {
    throw UnimplementedError('getDeviceList() has not been implemented.');
  }

  /// Connect to a USB printer.
  Future<bool> connect({required String? address}) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnect from the current USB printer.
  Future<bool> disconnect({required String? address}) {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Write data to the connected USB printer.
  Future<bool> write({required String? address, required List<int> bytes}) {
    throw UnimplementedError('write() has not been implemented.');
  }

  /// Write text to the connected USB printer.
  Future<bool> writeText({required String? address, required String text}) {
    throw UnimplementedError('writeText() has not been implemented.');
  }

  /// Read data from the connected USB printer.
  Future<List<int>?> read({required String? address, int timeout = 2000}) {
    throw UnimplementedError('read() has not been implemented.');
  }

  /// Stream of raw data received from the USB printer.
  Stream<USBDataEvent> get usbDataStream {
    throw UnimplementedError('usbDataStream has not been implemented.');
  }

  /// Stream of USB connection status.
  Stream<USBStatusEvent> get state {
    throw UnimplementedError('state has not been implemented.');
  }
}