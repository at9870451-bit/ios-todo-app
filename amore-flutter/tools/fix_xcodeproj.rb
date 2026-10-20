#!/usr/bin/env ruby
# 向 Runner 工程注入 Rust 静态库链接设置（绕过 pods 配置链的不确定性）
require 'xcodeproj'

project_path = File.expand_path('../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

lib_flags = '$(inherited) -force_load "$(SRCROOT)/../native/libs/ios/libamore_core.a"'

target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless target

target.build_configurations.each do |cfg|
  cfg.build_settings['OTHER_LDFLAGS'] = lib_flags
  cfg.build_settings['DEAD_CODE_STRIPPING'] = 'NO'
  cfg.build_settings['STRIP_INSTALLED_PRODUCT'] = 'NO'
  puts "#{cfg.name}: ldflags + strip 设置已注入"
end

project.save
puts 'Runner.xcodeproj 注入完成'
