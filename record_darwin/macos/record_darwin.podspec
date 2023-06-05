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
  
  s.source_files     = 'Classes/**/*'
  
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
