# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "appbundler-example-app"
  spec.version       = "1.0.0"
  spec.authors       = ["danielsdeleo"]
  spec.email         = ["dan@chef.io"]
  spec.description   = %q{test fixture app}
  spec.summary       = spec.description
  spec.homepage      = ""
  spec.license       = "Apache2"

  spec.files         = Dir.glob("{bin,lib,spec}/**/*").reject { |f| File.directory?(f) }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "chef"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
end
