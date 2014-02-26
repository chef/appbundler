# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'appbundler/version'

Gem::Specification.new do |spec|
  spec.name          = "appbundler"
  spec.version       = Appbundler::VERSION
  spec.authors       = ["danielsdeleo"]
  spec.email         = ["dan@opscode.com"]
  spec.description   = %q{Extracts a dependency solution from bundler's Gemfile.lock to speed gem activation}
  spec.summary       = spec.description
  spec.homepage      = ""
  spec.license       = "Apache2"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 2.13"
  spec.add_development_dependency "pry"
end
