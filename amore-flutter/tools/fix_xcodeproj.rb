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
  # 未签名构建（Flutter --no-codesign 下 pods 路径仍可能要求 team）
  cfg.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  cfg.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  cfg.build_settings['CODE_SIGN_IDENTITY'] = ''
  puts "#{cfg.name}: ldflags + strip + 签名禁用 已注入"
end

project.save
puts 'Runner.xcodeproj 注入完成'
