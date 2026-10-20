Pod::Spec.new do |s|
  s.name             = 'amore_core'
  s.version          = '0.1.0'
  s.summary          = 'Amore Rust Core static library (iOS)'
  s.description      = 'Amore 共享运行时：Rust 编译的静态库，经 C FFI JSON 总线与 Flutter UI 通信。'
  s.homepage         = 'https://github.com/at9870451-bit/ios-todo-app'
  s.license          = { :type => 'MIT' }
  s.authors          = { 'Amore' => 'dev@quantokx.local' }
  s.source           = { :path => '.' }

  # CI 构建产物（cargo build --target aarch64-apple-ios）
  s.vendored_libraries = 'ios/libamore_core.a'
  s.source_files       = 'amore_core.h'
  s.public_header_files = 'amore_core.h'

  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  # 关键：-force_load 把静态库全部符号拉进 Runner 二进制。
  # Dart ffi 用 DynamicLibrary.process() 按名查找 amore_call/amore_free，
  # 若不强制加载，链接器会因为没有 ObjC/Swift 引用而丢弃整个 object file。
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -force_load "${PODS_ROOT}/../native/libs/ios/libamore_core.a"'
  }
end
