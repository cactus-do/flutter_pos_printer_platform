import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../utils.dart'; // for toPixel and ImageData

class EscPosImageParams {
  final Uint8List imageBytes;
  final int paperWidth;
  final int dpi;
  final int threshold;

  EscPosImageParams({
    required this.imageBytes,
    required this.paperWidth,
    required this.dpi,
    this.threshold = 150,
  });
}

class TsplImageParams {
  final Uint8List imageBytes;
  final int sizeWidth;
  final int sizeHeight;
  final int dpi;

  TsplImageParams({
    required this.imageBytes,
    required this.sizeWidth,
    required this.sizeHeight,
    this.dpi = 200,
  });
}

class ImageRaster {
  ImageRaster({required this.data, required this.width, required this.height});
  final List<int> data;
  final int width; // width in bytes
  final int height; // height in dots
}

// Top-level function for compute
Future<ImageRaster> processEscPosImageTask(EscPosImageParams params) async {
  final decodedImage = img.decodeImage(params.imageBytes);
  if (decodedImage == null) throw Exception('Failed to decode image');

  final converted = toPixel(
    ImageData(width: decodedImage.width, height: decodedImage.height),
    paperWidth: params.paperWidth,
    dpi: params.dpi,
    isTspl: false,
  );

  final resizedImage = img.copyResize(
    decodedImage,
    width: converted.width,
    height: converted.height,
    interpolation: img.Interpolation.cubic,
  );

  final rasterData = _toEscPosRaster(resizedImage, threshold: params.threshold);

  final int widthBytes = (resizedImage.width + 7) ~/ 8;
  return ImageRaster(data: rasterData, width: widthBytes, height: resizedImage.height);
}

// Top-level function for compute
Future<ImageRaster> processTsplImageTask(TsplImageParams params) async {
  final decodedImage = img.decodeImage(params.imageBytes);
  if (decodedImage == null) throw Exception('Failed to decode image');

  final int multiplier = params.dpi == 200 ? 8 : 12;
  // TSPL resizing logic from TsplGenerator
  final resizedImage = img.copyResize(decodedImage,
      width: params.sizeWidth * multiplier, height: params.sizeHeight * multiplier, interpolation: img.Interpolation.linear);

  return _toTsplRaster(resizedImage);
}

// Helper: Convert to ESC/POS raster with Floyd-Steinberg dithering
List<int> _toEscPosRaster(img.Image image, {int threshold = 150}) {
  final int widthPx = image.width;
  final int heightPx = image.height;
  final int widthBytes = (widthPx + 7) ~/ 8;

  // Convert to grayscale list (0-255) for error diffusion
  final List<double> grayPixels = List<double>.filled(widthPx * heightPx, 0);

  // 1. Convert to Grayscale
  // Loop using Pixel API
  for (final pixel in image) {
    // In image v4, pixel is a convenient iterator/object
    // coordinates: pixel.x, pixel.y
    final int index = pixel.y * widthPx + pixel.x;

    // Pixel channels (normalized or int?)
    // pixel.r, pixel.g, pixel.b, pixel.a are num.
    // Usually 0-255 for int formats.

    // If transparent, treat as white (255)
    if (pixel.a < 128) {
      grayPixels[index] = 255;
    } else {
      // Luminance
      grayPixels[index] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
    }
  }

  // 2. Apply Floyd-Steinberg Dithering
  for (int y = 0; y < heightPx; y++) {
    for (int x = 0; x < widthPx; x++) {
      final int i = y * widthPx + x;
      final double oldPixel = grayPixels[i];
      final double newPixel = oldPixel < 128 ? 0 : 255; // Threshold at 128 for pure BW
      grayPixels[i] = newPixel;

      final double quantError = oldPixel - newPixel;

      if (x + 1 < widthPx) {
        grayPixels[y * widthPx + (x + 1)] += quantError * 7 / 16;
      }
      if (x - 1 >= 0 && y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + (x - 1)] += quantError * 3 / 16;
      }
      if (y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + x] += quantError * 5 / 16;
      }
      if (x + 1 < widthPx && y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + (x + 1)] += quantError * 1 / 16;
      }
    }
  }

  // 3. Pack bits
  List<int> rasterData = [];
  for (int y = 0; y < heightPx; y++) {
    for (int byteX = 0; byteX < widthBytes; byteX++) {
      int packedByte = 0;
      for (int bit = 0; bit < 8; bit++) {
        final int x = byteX * 8 + bit;
        if (x < widthPx) {
          final int i = y * widthPx + x;
          // Black (0) sets the bit?
          // ESC/POS: 1 = Black, 0 = White.
          // In my dither logic: newPixel 0 = Black, 255 = White.
          // So if grayPixels[i] == 0 (Black), set bit 1.

          if (grayPixels[i] < 128) {
            packedByte |= (0x80 >> bit);
          }
        }
      }
      rasterData.add(packedByte);
    }
  }
  return rasterData;
}

// Helper: Convert to TSPL raster with Floyd-Steinberg dithering
ImageRaster _toTsplRaster(img.Image image) {
  final int widthPx = image.width;
  final int heightPx = image.height;
  final int widthBytes = widthPx ~/ 8;

  // Use same dithering logic
  final List<double> grayPixels = List<double>.filled(widthPx * heightPx, 0);

  for (final pixel in image) {
    final int index = pixel.y * widthPx + pixel.x;

    if (pixel.a < 128) {
      grayPixels[index] = 255; // White
    } else {
      grayPixels[index] = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
    }
  }

  // Dither
  for (int y = 0; y < heightPx; y++) {
    for (int x = 0; x < widthPx; x++) {
      final int i = y * widthPx + x;
      final double oldPixel = grayPixels[i];
      final double newPixel = oldPixel < 128 ? 0 : 255;
      grayPixels[i] = newPixel;

      final double quantError = oldPixel - newPixel;

      if (x + 1 < widthPx) {
        grayPixels[y * widthPx + (x + 1)] += quantError * 7 / 16;
      }
      if (x - 1 >= 0 && y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + (x - 1)] += quantError * 3 / 16;
      }
      if (y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + x] += quantError * 5 / 16;
      }
      if (x + 1 < widthPx && y + 1 < heightPx) {
        grayPixels[(y + 1) * widthPx + (x + 1)] += quantError * 1 / 16;
      }
    }
  }

  // Pack for TSPL
  List<int> rasterData = [];
  int byteBucket = 0;
  int bitCount = 0;

  for (int i = 0; i < grayPixels.length; i++) {
    // 0 = Black, 255 = White.
    // Target: White = 1, Black = 0.
    bool isWhite = grayPixels[i] > 128;

    if (isWhite) {
      byteBucket |= (1 << (7 - bitCount));
    }

    bitCount++;
    if (bitCount == 8) {
      rasterData.add(byteBucket);
      byteBucket = 0;
      bitCount = 0;
    }
  }

  return ImageRaster(data: rasterData, width: widthBytes, height: heightPx);
}

class ImageUtils {
  static Future<ImageRaster> processEscPosImage(EscPosImageParams params) async {
    return await compute(processEscPosImageTask, params);
  }

  static Future<ImageRaster> processTsplImage(TsplImageParams params) async {
    return await compute(processTsplImageTask, params);
  }
}
