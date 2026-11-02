# Добавляет в Xcode-проект Flutter цель PacketTunnel (Network Extension) с ядром Xray.
# Запуск из корня проекта: ruby scripts/ios_add_extension.rb 0.2.0 2
require 'xcodeproj'

version = ARGV[0] || '1.0.0'
build = ARGV[1] || '1'
bundle_id = 'ru.kuduzo.kuduzo'

proj = Xcodeproj::Project.open('ios/Runner.xcodeproj')
if proj.targets.any? { |t| t.name == 'PacketTunnel' }
  puts 'PacketTunnel уже есть'
  exit 0
end

app = proj.targets.find { |t| t.name == 'Runner' }
raise 'Не найдена цель Runner' unless app

ext = proj.new_target(:app_extension, 'PacketTunnel', :ios, '15.0', nil, :swift)

group = proj.main_group.new_group('PacketTunnel', 'PacketTunnel')
swift = group.new_file('PacketTunnelProvider.swift')
group.new_file('Info.plist')
group.new_file('PacketTunnel.entitlements')
geoip = group.new_file('geoip.dat')
ext.add_file_references([swift])
ext.add_resources([geoip])

core = proj.frameworks_group.new_file('../build/ios-core/Kuduzocore.xcframework', :group)
ext.frameworks_build_phase.add_file_reference(core)
ext.add_system_framework('NetworkExtension')

ext.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{bundle_id}.PacketTunnel"
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'PacketTunnel/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['CODE_SIGN_ENTITLEMENTS'] = 'PacketTunnel/PacketTunnel.entitlements'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = version
  s['CURRENT_PROJECT_VERSION'] = build
  s['SKIP_INSTALL'] = 'YES'
  s['ENABLE_BITCODE'] = 'NO'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
  s['OTHER_LDFLAGS'] = ['$(inherited)', '-lresolv']
  s['CODE_SIGN_STYLE'] = 'Automatic'
end

# Расширение встраивается в приложение (PlugIns). Фазу ставим до «Thin Binary» Flutter —
# иначе Xcode находит цикл зависимостей.
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
ref = embed.add_file_reference(ext.product_reference, true)
ref.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
thin = app.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  app.build_phases.delete(embed)
  app.build_phases.insert(app.build_phases.index(thin), embed)
end
app.add_dependency(ext)

app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/Runner.entitlements'
  c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
end

proj.save
puts 'PacketTunnel добавлен'
