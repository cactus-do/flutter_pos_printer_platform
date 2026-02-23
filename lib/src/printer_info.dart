class PrinterInfo {
  final String? _serialNumber;
  final String? macAddress;
  final String? model;
  final String? firmware;
  final String? manufacturer;

  PrinterInfo({
    String? serialNumber,
    this.macAddress,
    this.model,
    this.firmware,
    this.manufacturer,
  }) : _serialNumber = serialNumber;

  String? get serialNumber {
    final serial = _serialNumber;
    final model = this.model;
    if (serial?.isEmpty != false && model?.isEmpty != false) return null;
    if (serial?.isNotEmpty == true && model?.isNotEmpty == true) return '$serial-$model';
    return serial ?? model;
  }

  @override
  String toString() {
    return 'PrinterInfo(serialNumber: $serialNumber, macAddress: $macAddress, model: $model, firmware: $firmware, manufacturer: $manufacturer)';
  }
}
