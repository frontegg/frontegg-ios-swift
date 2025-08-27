Pod::Spec.new do |s|
  s.name             = 'FronteggSwift'
  s.version          = '1.2.46'
  s.summary          = 'A swift library for easy integrating iOS application with Frontegg Services'
  s.description      = 'Frontegg is an end-to-end user management platform for B2B SaaS, powering strategies from PLG to enterprise readiness. Easy migration, no credit card required'
  s.homepage         = 'https://github.com/frontegg/frontegg-ios-swift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Frontegg LTD' => 'info@frontegg.com' }
  s.source           = { :git => 'https://github.com/frontegg/frontegg-ios-swift.git', :tag => s.version.to_s }
  s.swift_version    = '5.5'
  s.platforms    = { :ios => '14.0' }
  s.source_files     = 'Sources/**/*.swift'
  s.ios.deployment_target = '14.0'
end
