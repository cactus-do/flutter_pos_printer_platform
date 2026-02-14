import Flutter

/// Minimal no-op iOS plugin.
/// iOS only supports TCP/Ethernet printing which is handled entirely in Dart.
/// This stub exists solely to satisfy Flutter's plugin registration requirements.
public class FlutterPosPrinterPlatformPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // No method channels needed — TCP printing is pure Dart (dart:io Socket).
    }
}
