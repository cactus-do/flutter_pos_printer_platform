enum PrinterType { usb, network }

enum USBStatus { none, connecting, connected }

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
  disconnected,
  connecting,
  connected,
}
