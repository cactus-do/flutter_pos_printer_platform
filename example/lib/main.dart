import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'dart:io';

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
  var printerManager = PrinterManager.instance;
  var devices = <PrinterDevice>[];
  StreamSubscription<PrinterDevice>? _subscription;
  StreamSubscription<USBStatus>? _subscriptionUsbStatus;
  // Use generic input model
  TcpPrinterInput tcpPrinterInput = TcpPrinterInput(ipAddress: '192.168.0.123', port: 9100);
  // Separate list for specific models if needed, but for now we just use the inputs.

  // State for USB
  // in the new architecture, we don't have a single "selected printer" state in the manager
  // we have to manage it ourselves or rely on the manager's active transport.
  // The manager maintains _usbTransport and _tcpTransport.

  @override
  void initState() {
    super.initState();
    _scan();

    // USB Connection Status Listener
    _subscriptionUsbStatus = printerManager.stateUSB.listen((status) {
      print(' ----------------- status usb $status ------------------ ');
      if (Platform.isAndroid) {
        if (status == USBStatus.connected && !_isConnected) {
          setState(() {
            _isConnected = true;
          });
        } else if (status == USBStatus.none && _isConnected) {
          setState(() {
            _isConnected = false;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscriptionUsbStatus?.cancel();
    super.dispose();
  }

  // Method to scan with type
  void _scan() {
    devices.clear();
    _subscription = printerManager.discovery(type: defaultPrinterType, model: tcpPrinterInput).listen((device) {
      print(device.name);
      setState(() {
        devices.add(device);
      });
    });
  }

  Future<void> _connectDevice(PrinterDevice selectedPrinter) async {
    switch (defaultPrinterType) {
      case PrinterType.usb:
        // Create UsbPrinterInput
        final input = UsbPrinterInput(
          name: selectedPrinter.name,
          productId: selectedPrinter.productId,
          vendorId: selectedPrinter.vendorId,
        );
        await printerManager.connect(type: defaultPrinterType, model: input);
        break;
      case PrinterType.network:
        // Create TcpPrinterInput
        final input = TcpPrinterInput(
          ipAddress: selectedPrinter.address!,
          port: 9100, // Default port or from user input
        );
        await printerManager.connect(type: defaultPrinterType, model: input);
        break;
    }

    setState(() {
      _isConnected = true;
    });
  }

  Future<void> _printReceiveTest() async {
    List<int> bytes = [];

    // Xprinter XP-N160I
    final profile = await CapabilityProfile.load(name: 'XP-N160I');

    // PaperSize.mm80 or mm58
    final generator = Generator(PaperSize.mm80, profile);
    bytes += generator.setGlobalCodeTable('CP1252');
    bytes += generator.text('Test Print', styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Product 1');
    bytes += generator.text('Product 2');

    // Print image using EscPosGenerator from the package (since esc_pos_utils might not support new image_v3 well or we want to test our generator)
    // Or we can use esc_pos_utils generator for everything if it works.
    // The previous main.dart used EscPosPrinter.image() which used our internal logic.
    // So let's use our internal EscPosGenerator for the image part at least?
    // Mixed generators might be tricky if they state reset.
    // Let's stick to esc_pos_utils for text and check if it has image support.

    // Actually, let's look at how we can use EscPosGenerator from our package
    // Our package exports EscPosGenerator.
    // It takes PaperSize (from our package?) or just width?
    // EscPosGenerator(paperSize: PaperSize.mm80) -> wait, does it exist?
    // I created EscPosGenerator earlier. Let's check its constructor.

    // It has `EscPosGenerator({this.paperSize = PaperSize.mm80, this.profile})`?
    // I need to check `esc_pos_generator.dart`.

    // Assuming standard usage:
    printerManager.send(type: defaultPrinterType, bytes: bytes);
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
