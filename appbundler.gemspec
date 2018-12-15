# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "appbundler/version"

Gem::Specification.new do |spec|
  spec.name          = "appbundler"
  spec.version       = Appbundler::VERSION
  spec.authors       = ["Chef Software, Inc."]
  spec.email         = ["info@chef.io"]
  spec.description   = %q{Extracts a dependency solution from bundler's Gemfile.lock to speed gem activation}
  spec.summary       = spec.description
  spec.homepage      = "https://github.com/chef/appbundler"
  spec.license       = "Apache-2.0"

  spec.files         = %w{LICENSE Gemfile} + Dir.glob("*.gemspec") + Dir.glob("{bin,lib}/**/*")
  spec.executables   = %w{appbundler}
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.3"

  spec.add_dependency "mixlib-shellout", "~> 2.0"
  spec.add_dependency "mixlib-cli", "~> 1.4"
end
