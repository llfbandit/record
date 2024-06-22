Pod::Spec.new do |s|
    s.name             = 'record_darwin'
    s.version          = '1.0.0'
    s.summary          = 'record package for iOS and macOS implementations'
    s.description      = <<-DESC
  A Flutter plugin for voice recording.
                         DESC
    s.homepage         = 'https://github.com/llfbandit/record/tree/master/record_darwin'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'llfbandit' => 'email@example.com' }
    s.source           = { :http => 'https://github.com/llfbandit/record/tree/master/record_darwin' }
    s.documentation_url = 'https://pub.dev/packages/record_darwin'
    s.source_files = 'Classes/**/*'
    s.public_header_files = 'Classes/**/*.h'
    s.swift_version    = '5.0'
    s.ios.dependency 'Flutter'
    s.osx.dependency 'FlutterMacOS'
    s.ios.deployment_target = '11.0'
    s.osx.deployment_target = '10.15'
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  end