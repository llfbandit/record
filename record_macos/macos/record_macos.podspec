Pod::Spec.new do |s|
    s.name             = 'record_macos'
    s.version          = '1.2.0'
    s.summary          = 'record package for macOS implementation'
    s.description      = <<-DESC
  A Flutter plugin for voice recording.
                         DESC
    s.homepage         = 'https://github.com/llfbandit/record/tree/master/record_macos'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'llfbandit' => 'email@example.com' }
    s.source           = { :http => 'https://github.com/llfbandit/record/tree/master/record_macos' }

    s.source_files     = 'record_macos/Sources/record_macos/**/*.swift'
    s.swift_version    = '5.0'
    s.dependency 'FlutterMacOS'
    s.platform         = :osx, '10.15'
    # Privacy manifest
    s.resource_bundles = {'record_macos_privacy' => ['record_macos/Sources/record_macos/Resources/PrivacyInfo.xcprivacy']}

    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  end