import 'package:flutter_pos_printer_platform_image_3/src/enums.dart';

class USBStatusEvent {
  final String address;
  final USBStatus status;

  USBStatusEvent({
    required this.address,
    required this.status,
  });
}

class USBDataEvent {
  final String address;
  final List<int> data;

  USBDataEvent({
    required this.address,
    required this.data,
  });
}

class USBInterfaceEvent {
  final String address;
  final USBInterfaceStatus status;

  USBInterfaceEvent({
    required this.address,
    required this.status,
  });
}