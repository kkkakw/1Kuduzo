Pod::Spec.new do |s|
  s.name             = 'kuduzo_vpn_ios'
  s.version          = '0.1.0'
  s.summary          = 'Kuduzo VPN: управление туннелем на iOS'
  s.description      = 'Канал Flutter к NETunnelProviderManager.'
  s.homepage         = 'https://vpnkuduzo.ru'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Kuduzo' => 'dev@kuduzo.local' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.frameworks       = 'NetworkExtension'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
