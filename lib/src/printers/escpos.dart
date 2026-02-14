import 'dart:typed_data';

import 'package:flutter_pos_printer_platform_image_3/printer.dart';
import 'package:flutter_pos_printer_platform_image_3/src/utils.dart';
import 'package:image_v3/image_v3.dart';

class EscPosPrinter<T> extends GenericPrinter<T> {
  EscPosPrinter(PrinterConnector<T> connector, T model, {this.dpi = 200, required this.width, this.beepCount = 4})
      : super(connector, model);

  final int width;
  final int dpi;
  final int beepCount;

  @override
  Future<bool> beep() async {
    return await sendToConnector(() => [
          0x1b, 0x42, // ESC B — Beep
          beepCount, // number of beeps
          0x05, // duration (50ms units)
        ]);
  }

  @override
  Future<bool> image(Uint8List image, {int threshold = 150}) async {
    final decodedImage = decodeImage(image)!;

    final converted = toPixel(
      ImageData(width: decodedImage.width, height: decodedImage.height),
      paperWidth: width,
      dpi: dpi,
      isTspl: false,
    );

    // Resize the image to fit the paper width
    final resizedImage = copyResize(
      decodedImage,
      width: converted.width,
      height: converted.height,
      interpolation: Interpolation.cubic,
    );

    // Convert to monochrome raster data for ESC/POS GS v 0
    final rasterData = _toEscPosRaster(resizedImage, threshold: threshold);

    // Calculate delay based on image height
    final ms = 1000 + (converted.height * 0.5).toInt();

    return await sendToConnector(() {
      List<int> bytes = [];

      // ESC @ — Initialize printer
      bytes += [0x1b, 0x40];

      // GS v 0 — Print raster bit image
      // Format: GS v 0 m xL xH yL yH d1...dk
      // m=0 (normal mode), xL/xH = width in bytes, yL/yH = height in dots
      final int widthBytes = (resizedImage.width + 7) ~/ 8; // round up to nearest byte
      final int heightDots = resizedImage.height;

      bytes += [
        0x1d, 0x76, 0x30, 0x00, // GS v 0 m(0=normal)
        widthBytes & 0xff, (widthBytes >> 8) & 0xff, // xL, xH
        heightDots & 0xff, (heightDots >> 8) & 0xff, // yL, yH
      ];

      bytes += rasterData;

      // Line feed after image
      bytes += [0x0a];

      return bytes;
    }, delayMs: ms);
  }

  /// Convert an image to ESC/POS raster format (1 bit per pixel).
  /// In ESC/POS raster mode: bit 1 = black dot, bit 0 = white dot.
  /// Data is packed MSB first, left to right, top to bottom.
  List<int> _toEscPosRaster(Image image, {int threshold = 150}) {
    final int widthPx = image.width;
    final int heightPx = image.height;
    final int widthBytes = (widthPx + 7) ~/ 8;
    final List<int> imageBytes = image.getBytes(format: Format.argb);

    List<int> rasterData = [];

    for (int y = 0; y < heightPx; y++) {
      for (int byteX = 0; byteX < widthBytes; byteX++) {
        int packedByte = 0;
        for (int bit = 0; bit < 8; bit++) {
          final int x = byteX * 8 + bit;
          if (x < widthPx) {
            final int pixelOffset = (y * widthPx + x) * 4; // ARGB = 4 bytes per pixel
            if (pixelOffset + 3 < imageBytes.length) {
              final int a = imageBytes[pixelOffset]; // Alpha
              final int r = imageBytes[pixelOffset + 1];
              final int g = imageBytes[pixelOffset + 2];
              final int b = imageBytes[pixelOffset + 3];

              // Convert to grayscale using luminance formula
              final int gray = (0.299 * r + 0.587 * g + 0.114 * b).toInt();

              // Transparent pixels are white, dark pixels (below threshold) are black
              final bool isBlack = a > 128 && gray < threshold;

              if (isBlack) {
                packedByte |= (0x80 >> bit); // Set bit (MSB first)
              }
            }
          }
          // Padding bits beyond image width remain 0 (white)
        }
        rasterData.add(packedByte);
      }
    }

    return rasterData;
  }

  @override
  Future<bool> pulseDrawer() async {
    return await sendToConnector(() => [0x1b, 0x70, 0x00, 0x1e, 0xff, 0x00]);
  }

  @override
  Future<bool> selfTest() async {
    // ESC/POS self-test: GS ( A — execute test print
    return await sendToConnector(() => [0x1d, 0x28, 0x41, 0x02, 0x00, 0x00, 0x02]);
  }

  @override
  Future<bool> setIp(String ipAddress) async {
    return await sendToConnector(() => encodeSetIP(ipAddress));
  }
}
