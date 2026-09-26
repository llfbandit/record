Pod::Spec.new do |s|
    s.name             = 'record_darwin'
    s.version          = '2.0.0'
    s.summary          = 'record package for iOS and macOS implementation'
    s.description      = <<-DESC
  A Flutter plugin for voice recording.
                         DESC
    s.homepage         = 'https://github.com/llfbandit/record/tree/main/record_darwin'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'llfbandit' => 'email@example.com' }
    s.source           = { :http => 'https://github.com/llfbandit/record/tree/main/record_darwin' }

    s.source_files     = [
      'record_darwin/Sources/record_darwin/core/**/*.swift',
      'record_darwin/Sources/record_darwin/channel/**/*.swift',
    ]
    s.ios.source_files = 'record_darwin/Sources/record_darwin/ios/**/*.swift'
    s.osx.source_files = 'record_darwin/Sources/record_darwin/macos/**/*.swift'
    s.swift_version    = '5.0'
    s.ios.dependency 'Flutter'
    s.osx.dependency 'FlutterMacOS'
    s.ios.deployment_target = '12.0'
    s.osx.deployment_target = '10.15'
    # Privacy manifest
    s.resource_bundles = {'record_darwin_privacy' => ['record_darwin/Sources/record_darwin/Resources/PrivacyInfo.xcprivacy']}

    # Flutter.framework does not contain a i386 slice.
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  end
