# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "appbundler/version"

Gem::Specification.new do |spec|
  spec.name          = "appbundler"
  spec.version       = Appbundler::VERSION
  spec.authors       = ["Dan DeLeo"]
  spec.email         = ["dan@chef.io"]
  spec.description   = %q{Extracts a dependency solution from bundler's Gemfile.lock to speed gem activation}
  spec.summary       = spec.description
  spec.homepage      = "https://github.com/chef/appbundler"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.2.0"

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "mixlib-shellout", "~> 2.0"

  spec.add_dependency "mixlib-cli", "~> 1.4"
end
