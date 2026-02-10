class PrinterInfo {
  final String? serialNumber;
  final String? macAddress;
  final String? model;
  final String? firmware;
  final String? manufacturer;

  PrinterInfo({
    this.serialNumber,
    this.macAddress,
    this.model,
    this.firmware,
    this.manufacturer,
  });

  @override
  String toString() {
    return 'PrinterInfo(serialNumber: $serialNumber, macAddress: $macAddress, model: $model, firmware: $firmware, manufacturer: $manufacturer)';
  }
}
