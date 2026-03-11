import 'package:flutter_pos_printer_platform_image_3/src/models/events.dart';

import '../platform_interface/flutter_pos_printer_platform.dart';
import '../enums.dart';

abstract class UsbStatusListener {
  static Stream<USBInterfaceEvent> get state {
    final _platform = FlutterPosPrinterPlatform.instance;
    return _platform.state.where((event) => event.status.isInterfaceEvent).map((event) {
      switch (event.status) {
        case USBStatus.deviceAttached:
          return USBInterfaceEvent(address: event.address, status: USBInterfaceStatus.deviceAttached);
        case USBStatus.deviceDetached:
          return USBInterfaceEvent(address: event.address, status: USBInterfaceStatus.deviceDetached);
        default:
          return USBInterfaceEvent(address: event.address, status: USBInterfaceStatus.unknown);
      }
    });
  }
}
