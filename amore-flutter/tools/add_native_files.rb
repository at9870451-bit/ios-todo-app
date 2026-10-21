# 把 ios/Runner 下自定义 Swift 文件加入 Runner target（跟随 AppDelegate 的既有分组语义）
require 'xcodeproj'

project_path = File.expand_path('../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless target

# 以 flutter create 生成的 AppDelegate.swift 所在 group 为锚点（同组同 sourceTree 语义）
app_ref = project.files.find { |f| f.path == 'AppDelegate.swift' || f.display_name == 'AppDelegate.swift' }
abort('AppDelegate.swift file reference not found') unless app_ref
group = app_ref.parent

added = 0
Dir[File.expand_path('../ios/Runner/*.swift', __dir__)].each do |path|
  name = File.basename(path)
  next if name == 'AppDelegate.swift'
  next if project.files.any? { |f| f.display_name == name || f.path == "Runner/#{name}" }
  ref = group.new_reference(name)
  ref.path = name
  target.add_file_references([ref])
  puts "Added #{name}"
  added += 1
end

# 资源文件（Resources/*.dae 等）→ Resources build phase
res_dir = File.expand_path('../ios/Runner/Resources', __dir__)
if File.directory?(res_dir)
  res_phase = target.resources_build_phase
  Dir["#{res_dir}/*"].each do |path|
    name = File.basename(path)
    next if project.files.any? { |f| f.display_name == name }
    ref = group.new_reference("Resources/#{name}")
    res_phase.add_file_reference(ref)
    puts "Added resource #{name}"
  end
end

project.save
puts "native files injected (#{added})"
