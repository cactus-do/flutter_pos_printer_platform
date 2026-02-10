import 'dart:io';

class PrinterDevice {
  String name;
  String operatingSystem = Platform.operatingSystem;
  String? vendorId;
  String? productId;
  String? address;
  String? serialNumber;
  String? model;
  String? manufacturer;

  PrinterDevice({
    required this.name,
    this.address,
    this.vendorId,
    this.productId,
    this.serialNumber,
    this.model,
    this.manufacturer,
  });
}
