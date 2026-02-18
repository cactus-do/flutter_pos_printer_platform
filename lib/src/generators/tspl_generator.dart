import 'dart:typed_data';
import '../utils/image_utils.dart';

class TsplCommand {
  static final String SIZE = "SIZE";
  static final String GAP = "GAP";
  static final String REFERENCE = "REFERENCE";
  static final String DIRECTION = "DIRECTION";
  static final String OFFSET = "OFFSET";
  static final String SHIFT = "SHIFT";

  static final String BEEP = "BEEP";
  static final String BITMAP = "BITMAP";
  static final String REVERSE = "REVERSE";
  static final String PRINT = "PRINT";
  static final String SELF_TEST_ETHERNET = "SELFTEST ETHERNET";
  static final String CLS = "CLS";
  static final String EOP = "EOP";

  static final String COMMA = ",";
  static final String EOL = "\r\n";
  static final List<int> EOL_HEX = [0x0d, 0x0a];

  static String setSize(String w, String h, String unit) => createLine(SIZE, [w + unit, h + unit]);
  static String setGap(String w, String h, String unit) => createLine(GAP, [w + unit, h + unit]);
  static String setReference(String x, String y) => createLine(REFERENCE, [x, y]);
  static String setDirection(String direction) => createLine(DIRECTION, [direction]);
  static String setOffset(String distance, String offset, String unit) => createLine(OFFSET, [distance + unit, offset + unit]);
  static String setShift(String shiftLeft, String shiftTop) => createLine(SHIFT, [shiftLeft, shiftTop]);
  static String imageString(String x, String y, String widthByte, String heightDot, {String mode = "0"}) =>
      createString(BITMAP, [x, y, widthByte, heightDot, mode, ""]);
  static String reverse(String x, String y, String widthByte, String heightDot) => createLine(REVERSE, [x, y, widthByte, heightDot]);
  static String printIt(String copy, {String repeat = "1"}) => createLine(PRINT, [copy, repeat]);
  static String beep() => createLine(BEEP, []);
  static String selfTest() => createLine(SELF_TEST_ETHERNET, []);
  static String clearCache() => createLine(CLS, []);
  static String close() => createLine(EOP, []);

  static String createLine(String command, List<String> args) => "${createString(command, args)} $EOL";
  static String createString(String command, List<String> args) => "$command ${args.join(COMMA)}";
}

class ImageRaster {
  ImageRaster({required this.data, required this.width, required this.height});
  final List<int> data;
  final String width;
  final String height;
}

class TsplGenerator {
  final String dpi;
  final String unit;
  final String sizeWidth;
  final String sizeHeight;
  final String gapDistance;
  final String gapOffset;
  final String referenceX;
  final String referenceY;
  final String direction;
  final String offset;
  final String offsetDistance;
  final String shiftLeft;
  final String shiftTop;

  late final String _config;

  TsplGenerator({
    this.unit = "mm",
    this.sizeWidth = "35",
    this.sizeHeight = "25",
    this.gapDistance = "5",
    this.gapOffset = "0",
    this.referenceX = "0",
    this.referenceY = "0",
    this.direction = "0",
    this.offset = "0",
    this.offsetDistance = "0",
    this.shiftLeft = "0",
    this.shiftTop = "0",
    this.dpi = "200",
  }) {
    _config = [
      TsplCommand.setSize(sizeWidth, sizeHeight, unit),
      TsplCommand.setGap(gapDistance, gapOffset, unit),
      TsplCommand.setReference(referenceX, referenceY),
      TsplCommand.setDirection(direction),
      TsplCommand.setOffset(offsetDistance, offset, unit),
      TsplCommand.setShift(shiftLeft, shiftTop)
    ].join();
  }

  List<int> beep() {
    return [...TsplCommand.clearCache().codeUnits, ...TsplCommand.beep().codeUnits, ...TsplCommand.close().codeUnits];
  }

  List<int> selfTest() {
    return [...TsplCommand.clearCache().codeUnits, ...TsplCommand.selfTest().codeUnits, ...TsplCommand.close().codeUnits];
  }

  List<int> setIp(String ip) {
    List<int> buffer = [0x1f, 0x1b, 0x1f, 0x91, 0x00, 0x49, 0x50];
    final List<String> splittedIp = ip.split('.');
    return buffer..addAll(splittedIp.map((e) => int.parse(e)).toList());
  }

  List<int> pulseDrawer() {
    return []; // TSPL usually doesn't control drawer like ESC/POS
  }

  Future<List<int>> image(Uint8List imageBytes) async {
    if (imageBytes.isEmpty) return [];

    final raster = await ImageUtils.processTsplImage(TsplImageParams(
      imageBytes: imageBytes,
      sizeWidth: int.parse(sizeWidth),
      sizeHeight: int.parse(sizeHeight),
      dpi: int.parse(dpi),
    ));

    List<int> buffer = [];
    buffer += _config.codeUnits;
    buffer += TsplCommand.clearCache().codeUnits;
    buffer += TsplCommand.imageString('0', '0', raster.width.toString(), raster.height.toString(), mode: '0').codeUnits;
    buffer += raster.data;
    buffer += TsplCommand.EOL_HEX;
    buffer += TsplCommand.printIt('1', repeat: '1').codeUnits;
    buffer += TsplCommand.close().codeUnits;
    return buffer;
  }
}
