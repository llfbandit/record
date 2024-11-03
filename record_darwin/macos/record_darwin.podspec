Pod::Spec.new do |s|
    s.name             = 'record_darwin'
    s.version          = '1.0.0'
    s.summary          = 'record package for macOS implementation'
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
    s.dependency 'FlutterMacOS'
    s.osx.deployment_target = '10.15'
    s.resource_bundles = {'record_darwin_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  end