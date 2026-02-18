import 'package:flutter_pos_printer_platform_image_3/src/enums.dart';

abstract class PrinterTransport {
  /// Connects to the printer.
  /// Implementations should throw specific exceptions on failure.
  Future<bool> connect();

  /// Disconnects from the printer.
  Future<bool> disconnect();

  /// Sends raw bytes to the printer.
  Future<bool> write(List<int> bytes);

  /// Helper to send a command + data transaction.
  /// Useful if the transport needs to reconnect for each transaction (e.g. HTTP, or stateless USB).
  Future<bool> send(List<int> bytes) => write(bytes);

  /// Stream of connection state.
  Stream<PosPrinterConnectionState> get state;
  Stream<PrinterStatus> get status;
}
