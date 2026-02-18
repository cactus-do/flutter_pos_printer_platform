# flutter_pos_printer_platform

[![Pub Version](https://img.shields.io/badge/pub-v1.2.3-green)](https://pub.dev/packages/flutter_pos_printer_platform_image_3)

Notice: This library was initially forked from [arthas1888](https://github.com/arthas1888/flutter_pos_printer_platform) in order to use it in a flutter project that use both image v4 and image v3 dart libraries. And since then, the library received many bug fixes after the original library was [discontinued](https://pub.dev/packages/flutter_pos_printer_platform).

--------------------------

A library to discover printers, and send printer commands.

This library allows to print esc commands to printers in different platforms such as android, ios, windows and different interfaces as Bluetooth and BLE, USB and Wifi/Ethernet

Inspired by [flutter_pos_printer](https://github.com/feedmepos/flutter_printer/tree/master/packages/flutter_pos_printer).


## Main Features
* Android, iOS and Windows support
* **Parallel Printer Support**: Connect to multiple printers simultaneously, each with its own heartbeat.
* **Identity-First Discovery**: Resolve Serial Numbers for network printers to handle DHCP changes.
* Send raw `List<int> bytes` data to a device.

## Features

|                         |      Android       |         iOS          |      Windows       |            Description            |
| :---------------        | :----------------: | :------------------: | :----------------: | :-------------------------------- |
| USB interface           | :white_check_mark: |  :white_square_button: | :white_check_mark: | Allows connection with usb devices. |
| Net (ethernet/wifi) interface | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Allows connection with network devices. |
| scan                    | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Starts a scan for network or USB devices. |
| connect                 | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Establishes a connection to the device. |
| disconnect              | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Cancels an active or pending connection to the device. |
| state                   | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Stream of connection state changes. |
| status                  | :white_check_mark: |  :white_check_mark:  | :white_check_mark: | Stream of printer status (Paper low/out). |

## How to use it

### 1. Discovery
Use the static discovery methods from the specific driver.

```dart
// Network Discovery with Identity (Serial Number) resolution
TcpTransport.discovery(resolveIdentity: true).listen((device) {
    print('Found: ${device.address} (SN: ${device.serialNumber})');
});

// USB Discovery
UsbTransport.discovery().listen((device) {
    print('Found: ${device.name}');
});
```

### 2. Multi-Printer Management
Maintain your own fleet of independent transports.

```dart
final kitchen = TcpTransport(ipAddress: '192.168.1.50');
final bar = TcpTransport(ipAddress: '192.168.1.51');

// Each has its own HEARTBEAT and STATUS
kitchen.status.listen((status) {
  if (status == PrinterStatus.paperOut) print("Kitchen is out of paper!");
});

await kitchen.connect();
await bar.connect();
```

### 3. Send bytes to print
```dart
    _sendBytesToPrint(List<int> bytes, PrinterTransport transport) async { 
      await transport.send(bytes);
    }
```

## Troubleshooting

error:'State restoration of CBCentralManager is only allowed for applications that have specified the "bluetooth-central" background mode'
info.plist add:

```
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Allow App use bluetooth?</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Allow App use bluetooth?</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
</array>
```


## Credits
- https://github.com/andrey-ushakov/esc_pos_utils
- https://github.com/bailabs/esc-pos-printer-flutter
- https://github.com/feedmepos/flutter_printer/tree/master/packages/flutter_pos_printer
- https://pub.dev/packages/flutter_pos_printer_platform


## Support Original Author

If you think that this project has helped you with your developments, you can support this project, any support is much appreciated.

[![Paypal](https://raw.githubusercontent.com/arthas1888/flutter_pos_printer_platform/main/btn-sm-paypal-payment.png)](https://www.paypal.com/donate/?hosted_button_id=92HK6VNCK7MUY)