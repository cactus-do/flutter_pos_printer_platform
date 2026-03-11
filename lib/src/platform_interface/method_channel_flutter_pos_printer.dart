import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pos_printer_platform_image_3/src/models/events.dart';

import 'flutter_pos_printer_platform.dart';
import '../enums.dart';

class MethodChannelFlutterPosPrinter extends FlutterPosPrinterPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('com.cactus.flutter_pos_printer_platform');

  @visibleForTesting
  final EventChannel stateChannel = const EventChannel('com.cactus.flutter_pos_printer_platform/usb_state');

  @visibleForTesting
  final EventChannel dataChannel = const EventChannel('com.cactus.flutter_pos_printer_platform/usb_data');

  Stream<USBStatusEvent>? _statusStream;
  Stream<USBDataEvent>? _dataStream;

  // =========================
  // Devices
  // =========================

  @override
  Future<List<Map<String, dynamic>>> getDeviceList() async {
    final List<dynamic>? result = await methodChannel.invokeMethod('getList');
    if (result == null) return [];

    return result.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // =========================
  // Connection
  // =========================

  @override
  Future<bool> connect({required String? address}) async {
    if (address == null) {
      print('Address is null');
      return false;
    }

    if (!Platform.isAndroid) return false;

    final bool? result = await methodChannel.invokeMethod<bool>('connectPrinter', {'address': address});
    return result ?? false;
  }

  @override
  Future<bool> disconnect({required String? address}) async {
    if (address == null) {
      print('Address is null');
      return false;
    }

    if (!Platform.isAndroid) return false;

    final bool? result = await methodChannel.invokeMethod<bool>('disconnectPrinter', {'address': address});
    return result ?? false;
  }

  // =========================
  // Write
  // =========================

  @override
  Future<bool> write({
    required String? address,
    required List<int> bytes,
  }) async {
    if (address == null) {
      print('Address is null');
      return false;
    }

    if (!Platform.isAndroid) return false;

    final bool? result = await methodChannel.invokeMethod<bool>('printBytes', {'address': address, 'bytes': bytes});
    return result ?? false;
  }

  @override
  Future<bool> writeText({
    required String? address,
    required String text,
  }) async {
    if (address == null) {
      print('Address is null');
      return false;
    }

    if (!Platform.isAndroid) return false;

    final bool? result = await methodChannel.invokeMethod<bool>('printText', {'address': address, 'text': text});
    return result ?? false;
  }

  // =========================
  // Streams
  // =========================

  @override
  Stream<USBStatusEvent> get state {
    _statusStream ??= stateChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return USBStatusEvent(
        address: map['address'].toString(),
        status: USBStatus.values[map['state'] as int],
      );
    }).asBroadcastStream();
    return _statusStream!;
  }

  @override
  Stream<USBDataEvent> get usbDataStream {
    _dataStream ??= dataChannel.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return USBDataEvent(
        address: map['address'].toString(),
        data: List<int>.from(map['data']),
      );
    }).asBroadcastStream();
    return _dataStream!;
  }
}
