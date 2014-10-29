# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "example-app"
  spec.version       = "1.0.0"
  spec.authors       = ["danielsdeleo"]
  spec.email         = ["dan@opscode.com"]
  spec.description   = %q{test fixture app}
  spec.summary       = spec.description
  spec.homepage      = ""
  spec.license       = "Apache2"

  spec.files         = Dir.glob("{lib,spec}/**/*").reject {|f| File.directory?(f) }
  spec.executables   = %w(app-binary-1 app-binary-2)
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "chef"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
end

