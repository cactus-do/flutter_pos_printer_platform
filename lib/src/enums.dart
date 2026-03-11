enum PrinterType { usb, network }

enum USBStatus {
  disconnected,
  connecting,
  connected,
  permissionNeeded,
  permissionGranted,
  permissionDenied,
  deviceAttached,
  deviceDetached,
}

extension USBStatusExtension on USBStatus {
  static const _printerEvents = [
    USBStatus.disconnected,
    USBStatus.connected,
    USBStatus.permissionDenied,
    USBStatus.permissionGranted,
    USBStatus.connecting,
    USBStatus.permissionNeeded,
  ];

  static const _interfaceEvents = [
    USBStatus.deviceAttached,
    USBStatus.deviceDetached,
  ];

  bool get isPrinterStatus => _printerEvents.contains(this);
  bool get isInterfaceEvent => _interfaceEvents.contains(this);
}

enum USBInterfaceStatus { deviceAttached, deviceDetached, unknown }

enum PrinterStatus {
  good,
  offline,
  paperLow,
  paperOut,
  coverOpen,
  printing,
  unknown,
}

enum PosPrinterConnectionState {
  unknown,
  disconnected,
  connecting,
  connected,
  permissionNeeded,
  permissionGranted,
  permissionDenied,
}
