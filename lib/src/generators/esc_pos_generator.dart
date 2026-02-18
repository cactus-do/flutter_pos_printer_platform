import 'dart:typed_data';
import '../utils/image_utils.dart';

class EscPosGenerator {
  final int width;
  final int dpi;
  final int beepCount;

  EscPosGenerator({this.dpi = 200, required this.width, this.beepCount = 4});

  List<int> beep() {
    return [
      0x1b, 0x42, // ESC B — Beep
      beepCount, // number of beeps
      0x05, // duration (50ms units)
    ];
  }

  List<int> pulseDrawer() {
    return [0x1b, 0x70, 0x00, 0x1e, 0xff, 0x00];
  }

  List<int> selfTest() {
    // ESC/POS self-test: GS ( A
    return [0x1d, 0x28, 0x41, 0x02, 0x00, 0x00, 0x02];
  }

  List<int> setIp(String ip) {
    List<int> buffer = [0x1f, 0x1b, 0x1f, 0x91, 0x00, 0x49, 0x50];
    final List<String> splittedIp = ip.split('.');
    return buffer..addAll(splittedIp.map((e) => int.parse(e)).toList());
  }

  List<int> cut() {
    return [0x1d, 0x56, 0x42, 0x00]; // GS V m n (Partial cut)
  }

  /// Generates commands to print an image.
  /// Note: This performs image processing in an isolate.
  Future<List<int>> image(Uint8List imageBytes, {int threshold = 150}) async {
    final raster = await ImageUtils.processEscPosImage(EscPosImageParams(
      imageBytes: imageBytes,
      paperWidth: width,
      dpi: dpi,
      threshold: threshold,
    ));

    List<int> bytes = [];

    // ESC @ — Initialize printer
    bytes += [0x1b, 0x40];

    // GS v 0 — Print raster bit image
    // Format: GS v 0 m xL xH yL yH d1...dk
    // xL/xH = width in bytes, yL/yH = height in dots
    final int widthBytes = raster.width;
    final int heightDots = raster.height;

    bytes += [
      0x1d, 0x76, 0x30, 0x00, // GS v 0 m(0=normal)
      widthBytes & 0xff, (widthBytes >> 8) & 0xff, // xL, xH
      heightDots & 0xff, (heightDots >> 8) & 0xff, // yL, yH
    ];

    bytes += raster.data;

    // Line feed after image
    bytes += [0x0a];

    return bytes;
  }
}
