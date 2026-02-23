import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_pos_printer_platform.dart';
import '../enums.dart'; // for USBStatus

/// An implementation of [FlutterPosPrinterPlatform] that uses method channels.
class MethodChannelFlutterPosPrinter extends FlutterPosPrinterPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('com.cactus.flutter_pos_printer_platform');

  @visibleForTesting
  final eventChannel = const EventChannel('com.cactus.flutter_pos_printer_platform/usb_state');

  @visibleForTesting
  final dataChannel = const EventChannel('com.cactus.flutter_pos_printer_platform/usb_data');

  Stream<USBStatus>? _statusStream;
  Stream<List<int>>? _dataStream;

  @override
  Future<List<dynamic>> getDeviceList() async {
    final List<dynamic>? results = await methodChannel.invokeMethod('getList');
    return results ?? [];
  }

  @override
  Future<bool> connect({String? name, String? vendorId, String? productId, String? address}) async {
    if (Platform.isAndroid) {
      if (vendorId == null || productId == null) return false;
      final params = {"vendor": int.tryParse(vendorId) ?? 0, "product": int.tryParse(productId) ?? 0, "address": address};
      // Method channel returns boolean
      final bool? result = await methodChannel.invokeMethod<bool>('connectPrinter', params);
      return result ?? false;
    } else if (Platform.isWindows) {
      if (name == null) return false;
      final params = {"name": name};
      final int? result = await methodChannel.invokeMethod<int>('connectPrinter', params);
      return result == 1;
    }
    return false;
  }

  @override
  Future<bool> disconnect() async {
    final result = await methodChannel.invokeMethod('close');
    if (result is bool) return result;
    if (result is int) return result == 1;
    return false;
  }

  @override
  Future<bool> write(List<int> bytes) async {
    final params = {"bytes": Uint8List.fromList(bytes)};
    final result = await methodChannel.invokeMethod('printBytes', params);

    if (result is bool) return result;
    if (result is int) return result == 1;
    return false;
  }

  @override
  Future<List<int>?> read({int timeout = 2000}) async {
    try {
      final params = {"timeout": timeout};
      final result = await methodChannel.invokeMethod<List<dynamic>>('read', params);
      if (result != null) {
        return result.cast<int>();
      }
    } catch (e) {
      debugPrint("Error reading from USB: $e");
    }
    return null;
  }

  @override
  Stream<USBStatus> get state {
    _statusStream ??= eventChannel.receiveBroadcastStream().map((event) {
      if (event is int) {
        if (event >= 0 && event < USBStatus.values.length) {
          return USBStatus.values[event];
        }
      }
      return USBStatus.none;
    }).asBroadcastStream();
    return _statusStream!;
  }

  @override
  Stream<List<int>> get usbDataStream {
    _dataStream ??= dataChannel.receiveBroadcastStream().map((event) {
      if (event is List) {
        return event.cast<int>();
      }
      return <int>[];
    }).asBroadcastStream();
    return _dataStream!;
  }
}
