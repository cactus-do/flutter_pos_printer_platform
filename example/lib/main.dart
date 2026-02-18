import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Printer Type
  var defaultPrinterType = PrinterType.usb;
  var _isConnected = false;

  // DRIVER-FIRST ARCHITECTURE:
  // Instead of a single manager, we maintain our own fleet of drivers
  final Map<String, PrinterTransport> _activePrinters = {};

  var devices = <PrinterDevice>[];
  StreamSubscription<PrinterDevice>? _subscription;

  // We keep a dedicated USB transport for the single USB slot
  UsbTransport _usbTransport = UsbTransport();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    // In a real app, you'd close all active transports here
    for (var transport in _activePrinters.values) {
      transport.disconnect();
    }
    super.dispose();
  }

  // Method to scan with type
  void _scan() {
    setState(() {
      devices.clear();
    });

    // We use the driver's discovery directly
    final stream = (defaultPrinterType == PrinterType.usb)
        ? UsbTransport.discovery()
        : TcpTransport.discovery(resolveIdentity: true); // We want Serial Numbers

    _subscription?.cancel();
    _subscription = stream.listen((device) {
      print('Found: ${device.name} (SN: ${device.serialNumber})');
      setState(() {
        devices.add(device);
      });
    });
  }

  Future<void> _connectDevice(PrinterDevice selectedPrinter) async {
    PrinterTransport transport;

    if (defaultPrinterType == PrinterType.usb) {
      // For USB, we update our dedicated transport
      _usbTransport = UsbTransport(
        name: selectedPrinter.name,
        productId: selectedPrinter.productId,
        vendorId: selectedPrinter.vendorId,
      );
      transport = _usbTransport;
    } else {
      // For Network, we create a new instance for this specific printer
      // Use IP as the temporary key or Serial Number if available
      final String id = selectedPrinter.serialNumber ?? selectedPrinter.address!;

      transport = TcpTransport(
        ipAddress: selectedPrinter.address!,
        port: 9100,
      );
      _activePrinters[id] = transport;
    }

    // Connect individual driver
    final success = await transport.connect();

    if (success) {
      // Every printer now has its OWN heartbeat and status listeners
      transport.status.listen((status) {
        print('PRINTER STATUS CHANGED: $status');
      });

      setState(() {
        _isConnected = true;
      });
    }
  }

  Future<void> _printReceiveTest() async {
    List<int> bytes = [];

    // Xprinter XP-N160I
    final profile = await CapabilityProfile.load(name: 'XP-N160I');
    final generator = Generator(PaperSize.mm80, profile);

    bytes += generator.setGlobalCodeTable('CP1252');
    bytes += generator.text('Fleet Printing Test', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('This is a direct-driver setup.');

    // Send to all active printers in parallel!
    for (var transport in _activePrinters.values) {
      transport.send(bytes);
    }

    // Also send to USB if connected
    if (defaultPrinterType == PrinterType.usb) {
      _usbTransport.send(bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Pos Printer Platform'),
        ),
        body: Center(
          child: Container(
            height: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isConnected
                                ? null
                                : () {
                                    setState(() {
                                      defaultPrinterType = PrinterType.usb;
                                      _scan();
                                    });
                                  },
                            child: const Text('USB'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isConnected
                                ? null
                                : () {
                                    setState(() {
                                      defaultPrinterType = PrinterType.network;
                                      _scan();
                                    });
                                  },
                            child: const Text('Network'),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Device List
                  Column(
                    children: devices.map((device) {
                      return ListTile(
                        title: Text('${device.name}'),
                        subtitle: Text("${device.vendorId} - ${device.productId}"),
                        onTap: () {
                          _connectDevice(device);
                        },
                        // leading: Icon(Icons.usb),
                      );
                    }).toList(),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ElevatedButton(
                      onPressed: _isConnected ? () => _printReceiveTest() : null,
                      child: const Text('Test Print'),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
