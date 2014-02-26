require "appbundler/version"
require 'pp'

module Appbundler

  class App
    attr_accessor :gemfile_lock
    attr_accessor :name

    def demo
      @gemfile_lock = "/Users/ddeleo/oc/chef/Gemfile.lock"
      @name = "chef"
      puts runtime_activate
    end

    def runtime_activate
      statements = runtime_dep_specs.map {|s| %Q|gem "#{s.name}", "= #{s.version}"|}
      activate_code = statements.join("\n")
      activate_code << "\n"
      activate_code << %Q|$:.unshift "#{app_lib_dir}"\n|
      activate_code
    end

    def app_lib_dir
      app_root = File.expand_path("..", gemfile_lock)
      File.join(app_root, "lib")
    end

    def runtime_dep_specs
      add_dependencies_from(app_spec)
    end

    def app_dependency_names
      @app_dependency_names ||= app_spec.dependencies.map(&:name)
    end

    def app_spec
      spec_for(name)
    end

    def gemfile_lock_specs
      parsed_gemfile_lock.specs
    end

    def parsed_gemfile_lock
      @parsed_gemfile_lock ||= Bundler::LockfileParser.new(IO.read(gemfile_lock))
    end

    private

    def add_dependencies_from(spec, collected_deps=[])
      spec.dependencies.each do |dep|
        next if collected_deps.any? {|s| s.name == dep.name }
        next_spec = spec_for(dep.name)
        collected_deps << next_spec
        add_dependencies_from(next_spec, collected_deps)
      end
      collected_deps
    end

    def spec_for(dep_name)
      gemfile_lock_specs.find {|s| s.name == dep_name } or raise "No spec #{dep_name}"
    end
  end

end

if __FILE__ == $PROGRAM_NAME
  Appbundler::App.new.demo
end
