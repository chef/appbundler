require "appbundler/version"
require 'pp'

module Appbundler

  class App
    attr_accessor :app_root

    def demo
      @app_root = "/Users/ddeleo/oc/chef"

      knife = app_executables.grep(/knife/).first
      puts binstub(knife)
    end

    def name
      File.basename(app_root)
    end

    def gemfile_lock
      File.join(app_root, "Gemfile.lock")
    end

    def shebang
      "#!#{Gem.ruby}\n"
    end

    def env_sanitizer
      %Q{ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil}
    end

    def runtime_activate
      @runtime_activate ||= begin
        statements = runtime_dep_specs.map {|s| %Q|gem "#{s.name}", "= #{s.version}"|}
        activate_code = ""
        activate_code << env_sanitizer << "\n"
        activate_code << statements.join("\n") << "\n"
        activate_code << %Q|$:.unshift "#{app_lib_dir}"\n|
        activate_code
      end
    end

    def binstub(bin_file)
      shebang + runtime_activate + "Kernel.load '#{bin_file}'\n"
    end

    def app_executables
      bin_dir_glob = File.join(app_root, "bin", "*")
      Dir[bin_dir_glob]
    end

    def app_lib_dir
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
