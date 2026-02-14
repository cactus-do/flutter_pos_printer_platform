#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_pos_printer_platform.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_pos_printer_platform_image_3'
  s.version          = '2.0.0'
  s.summary          = 'Flutter POS printer platform plugin — USB and TCP/Ethernet support.'
  s.description      = <<-DESC
Flutter plugin for POS thermal printers via USB and TCP/Ethernet.
iOS supports TCP/Ethernet only (pure Dart implementation).
                       DESC
  s.homepage         = 'https://github.com/cactus-do/flutter_pos_printer_platform'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cactus Engineering' => 'eng@cactus.do' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
