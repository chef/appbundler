require "bundler"
require "fileutils"
require "pp"

module Appbundler

  class AppbundlerError < StandardError; end

  class InaccessibleGemsInLockfile < AppbundlerError; end

  class App

    BINSTUB_FILE_VERSION = 1

    attr_reader :bundle_path
    attr_reader :target_bin_dir
    attr_reader :name

    def initialize(bundle_path, target_bin_dir, name)
      @bundle_path = bundle_path
      @target_bin_dir = target_bin_dir
      @name = name
    end

    # Copy over any .bundler and Gemfile.lock files to the target gem
    # directory.  This will let us run tests from under that directory.
    def copy_bundler_env
      gem_path = app_gemspec.gem_dir
      # If we're already using that directory, don't copy (it won't work anyway)
      return if gem_path == File.dirname(gemfile_lock)
      FileUtils.install(gemfile_lock, gem_path, :mode => 0644)
      if File.exist?(dot_bundle_dir) && File.directory?(dot_bundle_dir)
        FileUtils.cp_r(dot_bundle_dir, gem_path)
        FileUtils.chmod_R("ugo+rX", File.join(gem_path, ".bundle"))
      end
    end

    def write_executable_stubs
      executables_to_create = executables.map do |real_executable_path|
        basename = File.basename(real_executable_path)
        stub_path = File.join(target_bin_dir, basename)
        [real_executable_path, stub_path]
      end

      executables_to_create.each do |real_executable_path, stub_path|
        File.open(stub_path, "wb", 0755) do |f|
          f.write(binstub(real_executable_path))
        end
        if RUBY_PLATFORM =~ /mswin|mingw|windows/
          batch_wrapper_path = "#{stub_path}.bat"
          File.open(batch_wrapper_path, "wb", 0755) do |f|
            f.write(batchfile_stub)
          end
        end
      end

      executables_to_create
    end

    def dot_bundle_dir
      File.join(bundle_path, ".bundle")
    end

    def gemfile_lock
      File.join(bundle_path, "Gemfile.lock")
    end

    def ruby
      Gem.ruby
    end

    def batchfile_stub
      ruby_relpath_windows = ruby_relative_path.tr("/", '\\')
      <<-E
@ECHO OFF
"%~dp0\\#{ruby_relpath_windows}" "%~dpn0" %*
E
    end

    # Relative path from #target_bin_dir to #ruby. This is used to
    # generate batch files for windows in a way that the package can be
    # installed in a custom location. On Unix we don't support custom
    # install locations so this isn't needed.
    def ruby_relative_path
      ruby_pathname = Pathname.new(ruby)
      bindir_pathname = Pathname.new(target_bin_dir)
      ruby_pathname.relative_path_from(bindir_pathname).to_s
    end

    def shebang
      "#!#{ruby} --disable-gems\n"
    end

    # A specially formatted comment that documents the format version of the
    # binstub files we generate.
    #
    # This comment should be unusual enough that we can reliably (enough)
    # detect whether a binstub was created by Appbundler and parse it to learn
    # what version of the format it uses. If we ever need to support reading or
    # mutating existing binstubs, we'll know what file version we're starting
    # with.
    def file_format_comment
      "#--APP_BUNDLER_BINSTUB_FORMAT_VERSION=#{BINSTUB_FILE_VERSION}--\n"
    end

    # Ruby code (as a string) that clears GEM_HOME and GEM_PATH environment
    # variables. In an omnibus context, this is important so users can use
    # things like rvm without accidentally pointing the app at rvm's
    # ruby and gems.
    #
    # Environment sanitization can be skipped by setting the
    # APPBUNDLER_ALLOW_RVM environment variable to "true". This feature
    # exists to make tests run correctly on travis.ci (which uses rvm).
    def env_sanitizer
      <<-EOS
ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil unless ENV["APPBUNDLER_ALLOW_RVM"] == "true"
require "rubygems"
::Gem.clear_paths
EOS
    end

    def runtime_activate
      @runtime_activate ||= begin
        statements = runtime_dep_specs.map { |s| %Q{gem "#{s.name}", "= #{s.version}"} }
        activate_code = ""
        activate_code << env_sanitizer << "\n"
        activate_code << statements.join("\n") << "\n"
        activate_code
      end
    end

    def binstub(bin_file)
      shebang + file_format_comment + runtime_activate + load_statement_for(bin_file)
    end

    def load_statement_for(bin_file)
      name, version = app_spec.name, app_spec.version
      bin_basename = File.basename(bin_file)
      <<-E
gem "#{name}", "= #{version}"

spec = Gem::Specification.find_by_name("#{name}", "= #{version}")
bin_file = spec.bin_file("#{bin_basename}")

Kernel.load(bin_file)
E
    end

    def executables
      spec = app_gemspec
      spec.executables.map { |e| spec.bin_file(e) }
    end

    def runtime_dep_specs
      add_dependencies_from(app_spec)
    end

    def app_dependency_names
      @app_dependency_names ||= app_spec.dependencies.map(&:name)
    end

    def app_gemspec
      Gem::Specification.find_by_name(app_spec.name, app_spec.version)
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

    # Bundler stores gems loaded from git in locations like this:
    # `lib/ruby/gems/2.1.0/bundler/gems/chef-b5860b44acdd`. Rubygems cannot
    # find these during normal (non-bundler) operation. This will cause
    # problems if there is no gem of the same version installed to the "normal"
    # gem location, because the appbundler executable will end up containing a
    # statement like `gem "foo", "= x.y.z"` which fails.
    #
    # However, if this gem/version has been manually installed (by building and
    # installing via `gem` commands), then we end up with the correct
    # appbundler file, even if it happens somewhat by accident.
    #
    # Therefore, this method lists all the git-sourced gems in the
    # Gemfile.lock, then it checks if that version of the gem can be loaded via
    # `Gem::Specification.find_by_name`. If there are any unloadable gems, then
    # the InaccessibleGemsInLockfile error is raised.
    def verify_deps_are_accessible!
      inaccessable_gems = inaccessable_git_sourced_gems
      return true if inaccessable_gems.empty?

      message = <<-MESSAGE
Application '#{name}' contains gems in the lockfile which are
not accessible by rubygems. This usually occurs when you fetch gems from git in
your Gemfile and do not install the same version of the gems beforehand.

MESSAGE

      message << "The Gemfile.lock is located here:\n- #{gemfile_lock}\n\n"

      message << "The offending gems are:\n"
      inaccessable_gems.each do |gemspec|
        message << "- #{gemspec.name} (#{gemspec.version}) from #{gemspec.source}\n"
      end

      message << "\n"

      message << "Rubygems is configured to search the following paths:\n"
      Gem.paths.path.each { |p| message << "- #{p}\n" }

      message << "\n"
      message << "If these seem wrong, you might need to set GEM_HOME or other environment\nvariables before running appbundler\n"

      raise InaccessibleGemsInLockfile, message
    end

    private

    def git_sourced_gems
      runtime_dep_specs.select { |i| i.source.kind_of?(Bundler::Source::Git) }
    end

    def inaccessable_git_sourced_gems
      git_sourced_gems.reject do |spec|
        gem_available?(spec)
      end
    end

    def gem_available?(spec)
      Gem::Specification.find_by_name(spec.name, "= #{spec.version}")
      true
    rescue Gem::LoadError
      false
    end

    def add_dependencies_from(spec, collected_deps = [])
      spec.dependencies.each do |dep|
        next if collected_deps.any? { |s| s.name == dep.name }
        # a bundler dep will not get pinned in Gemfile.lock
        next if dep.name == "bundler"
        next_spec = spec_for(dep.name)
        collected_deps << next_spec
        add_dependencies_from(next_spec, collected_deps)
      end
      collected_deps
    end

    def spec_for(dep_name)
      gemfile_lock_specs.find { |s| s.name == dep_name } || raise("No spec #{dep_name}")
    end
  end
end
