abstract class BasePrinterInput {}

class UsbPrinterInput extends BasePrinterInput {
  final String? name;
  final String? vendorId;
  final String? productId;

  UsbPrinterInput({this.name, this.vendorId, this.productId});
}

class TcpPrinterInput extends BasePrinterInput {
  final String ipAddress;
  final int port;
  final Duration timeout;

  TcpPrinterInput({
    required this.ipAddress,
    this.port = 9100,
    this.timeout = const Duration(seconds: 5),
  });
}
