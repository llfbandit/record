Pod::Spec.new do |s|
    s.name             = 'record_ios'
    s.version          = '1.2.0'
    s.summary          = 'record package for iOS implementation'
    s.description      = <<-DESC
  A Flutter plugin for voice recording.
                         DESC
    s.homepage         = 'https://github.com/llfbandit/record/tree/master/record_ios'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'llfbandit' => 'email@example.com' }
    s.source           = { :http => 'https://github.com/llfbandit/record/tree/master/record_ios' }

    s.source_files     = 'record_ios/Sources/record_ios/**/*.swift'
    s.swift_version    = '5.0'
    s.dependency 'Flutter'
    s.platform         = :ios, '12.0'
    # Privacy manifest
    s.resource_bundles = {'record_ios_privacy' => ['record_ios/Sources/record_ios/Resources/PrivacyInfo.xcprivacy']}

    # Flutter.framework does not contain a i386 slice.
    s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  end