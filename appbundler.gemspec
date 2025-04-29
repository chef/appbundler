lib = File.expand_path("lib", __dir__)
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

  spec.files         = Dir.glob("{bin,lib,spec}/**/*").reject { |f| File.directory?(f) } + %w{ LICENSE appbundler.gemspec Rakefile Gemfile }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "mixlib-shellout", ">= 2.0", "< 4.0"
  spec.add_dependency "mixlib-cli", ">= 1.4", "< 3.0"
  spec.add_dependency "yard"
  spec.add_dependency "fiddle"
end
