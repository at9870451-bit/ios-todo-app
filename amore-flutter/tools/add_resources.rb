# 把 ios/Runner/Resources 下的模型/贴图注入 Resources build phase（进 bundle）
require 'xcodeproj'

project_path = File.expand_path('../ios/Runner.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort('Runner target not found') unless target

app_ref = project.files.find { |f| f.path == 'AppDelegate.swift' || f.display_name == 'AppDelegate.swift' }
abort('AppDelegate.swift not found') unless app_ref
group = app_ref.parent

res_dir = File.expand_path('../ios/Runner/Resources', __dir__)
abort("Resources dir missing: #{res_dir}") unless File.directory?(res_dir)

res_phase = target.resources_build_phase
count = 0
Dir["#{res_dir}/*"].each do |path|
  name = File.basename(path)
  next if project.files.any? { |f| f.display_name == name }
  ref = group.new_reference("Resources/#{name}")
  res_phase.add_file_reference(ref)
  puts "Added resource #{name}"
  count += 1
end

project.save
puts "resources injected (#{count})"
