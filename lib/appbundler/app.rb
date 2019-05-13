require "bundler"
require "fileutils"
require "mixlib/shellout"
require "tempfile"
require "pp"

module Appbundler

  class AppbundlerError < StandardError; end

  class InaccessibleGemsInLockfile < AppbundlerError; end

  class App

    BINSTUB_FILE_VERSION = 1

    attr_reader :bundle_path
    attr_reader :target_bin_dir
    attr_reader :name

    # The bundle_path is always the path to the Gemfile.lock being used, e.g.
    # /var/cache/omnibus/src/chef/chef-14.10.9/Gemfile.lock or whatever.  If
    # the name if the gem is not set then we behave like old style 2-arg appbundling
    # where the gem we are appbundling is in the gemspec in that directory.
    #
    # If the name is not nil, then we are doing a multiple-app appbundle where
    # the Gemfile.lock is the omnibus Gemfile.lock and multiple app gems may be
    # appbundled against the same Gemfile.lock.
    #
    # @param bundle_path [String] the directory path of the Gemfile.lock
    # @param target_bin_dir [String] the binstub dir, e.g. /opt/chefdk/bin
    # @param name [String] name of the gem
    def initialize(bundle_path, target_bin_dir, name)
      @bundle_path = bundle_path
      @target_bin_dir = target_bin_dir
      @name = name
    end

    # For the 2-arg version this is the gemfile in the omnibus build directory:
    # /var/cache/omnibus/src/chef/chef-14.10.9/Gemfile
    #
    # For the 3-arg version this is the gemfile in the gems installed directory:
    # /opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/berkshelf-7.0.7/Gemfile
    #
    def gemfile_path
      "#{app_dir}/Gemfile"
    end

    def safe_resolve_local_gem(s)
      Gem::Specification.find_by_name(s.name, s.version)
    rescue Gem::MissingSpecError
      nil
    end

    def requirement_to_str(req)
      req.as_list.map { |r| "\"#{r}\"" }.join(", ")
    end

    # This is only used in the 3-arg version.  The gemfile_path is the path into the actual
    # installed gem, e.g.: /opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/berkshelf-7.0.7/Gemfile
    #
    # The gemfile_lock is the omnibus gemfile.lock which is in this case:
    # /var/cache/omnibus/src/chef-dk/chef-dk-3.8.14/Gemfile.lock
    #
    # This solves the app gems dependencies against the Gemfile.locks pins so that they do not
    # conflict (assuming such a solution can be found).
    #
    # The "without" argument here applies to the app's Gemfile.  There is no information in
    # a rendered Gemfile.lock about gem groupings (literally none of that information is ever
    # rendered by bundler into a Gemfile.lock -- open one up and look for yourself).  So this
    # without argument then applies only to the transitive gemfile locking creation.  This
    # codepath does not affect what gems we ship, and does not affect the generation of the
    # binstubs.
    #
    def requested_dependencies(without)
      Bundler.settings.temporary(without: without) do
        definition = Bundler::Definition.build(gemfile_path, gemfile_lock, nil)
        definition.send(:requested_dependencies)
      end
    end

    # This is a blatant ChefDK 2.0 hack.  We need to audit all of our Gemfiles, make sure
    # that github_changelog_generator is in its own group and exclude that group from all
    # of our appbundle calls.  But to ship ChefDK 2.0 we just do this.
    SHITLIST = [
      "github_changelog_generator",
    ].freeze

    # This is a check which is equivalent to asking if we are running 2-arg or 3-arg.  If
    # we have an "external_lockfile" that means the chef-dk omnibus Gemfile.lock, e.g.:
    # /var/cache/omnibus/src/chef-dk/chef-dk-3.8.14/Gemfile.lock is being merged with the
    # Gemfile in e.g. /opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/berkshelf-7.0.7/Gemfile.
    # Hence the lockfile is "external" to the gem (it made sense to me at the time).
    #
    # If it is not then we're dealing with a single gem install from a single project and not
    # doing any of the transitive locking and we generate a single set of binstubs from a single
    # app in a single Gemfile.lock
    #
    def external_lockfile?
      app_dir != bundle_path
    end

    # This loads the specs from the Gemfile.lock which is called on the command line and is in
    # the omnibus build space.
    #
    # Somewhat confusingly this is also the same as the "external" gemfile.lock, which was originally
    # called the "local" gemfile.lock here.  In either case it is something like:
    # /var/cache/omnibus/src/chef-dk/chef-dk-3.8.14/Gemfile.lock
    #
    def local_gemfile_lock_specs
      gemfile_lock_specs.map do |s|
        # if SHITLIST.include?(s.name)
        #  nil
        # else
        safe_resolve_local_gem(s)
        # end
      end.compact
    end

    # Copy over any .bundler and Gemfile.lock files to the target gem
    # directory.  This will let us run tests from under that directory.
    #
    # This is only on the 2-arg implementations pathway.  This is not used
    # for the 3-arg version.
    #
    def copy_bundler_env
      gem_path = installed_spec.gem_dir
      # If we're already using that directory, don't copy (it won't work anyway)
      return if gem_path == File.dirname(gemfile_lock)
      FileUtils.install(gemfile_lock, gem_path, mode: 0644)
      if File.exist?(dot_bundle_dir) && File.directory?(dot_bundle_dir)
        FileUtils.cp_r(dot_bundle_dir, gem_path)
        FileUtils.chmod_R("ugo+rX", File.join(gem_path, ".bundle"))
      end
    end

    # This is the implementation of the 3-arg version of writing the merged lockfiles,
    # when called with the 2-arg version it short-circuits, however, to the copy_bundler_env
    # version above.
    #
    # This code does not affect the generated binstubs at all.
    #
    def write_merged_lockfiles(without: [])
      unless external_lockfile?
        copy_bundler_env
        return
      end

      # handle external lockfile
      Tempfile.open(".appbundler-gemfile", app_dir) do |t|
        t.puts "source 'https://rubygems.org'"

        locked_gems = {}

        gemfile_lock_specs.each do |s|
          # next if SHITLIST.include?(s.name)
          spec = safe_resolve_local_gem(s)
          next if spec.nil?

          case s.source
          when Bundler::Source::Path
            locked_gems[spec.name] = %Q{gem "#{spec.name}", path: "#{spec.gem_dir}"}
          when Bundler::Source::Rubygems
            # FIXME: should add the spec.version as a gem requirement below
            locked_gems[spec.name] = %Q{gem "#{spec.name}", "= #{spec.version}"}
          when Bundler::Source::Git
            raise "FIXME: appbundler needs a patch to support Git gems"
          else
            raise "appbundler doens't know this source type"
          end
        end

        seen_gems = {}

        t.puts "# GEMS FROM GEMFILE:"

        requested_dependencies(without).each do |dep|
          next if SHITLIST.include?(dep.name)
          if locked_gems[dep.name]
            t.puts locked_gems[dep.name]
          else
            string = %Q{gem "#{dep.name}", #{requirement_to_str(dep.requirement)}}
            string << %Q{, platform: #{dep.platforms}} unless dep.platforms.empty?
            t.puts string
          end
          seen_gems[dep.name] = true
        end

        t.puts "# GEMS FROM LOCKFILE: "

        locked_gems.each do |name, line|
          next if SHITLIST.include?(name)
          next if seen_gems[name]
          t.puts line
        end

        t.close
        puts IO.read(t.path) # debugging
        Dir.chdir(app_dir) do
          FileUtils.rm_f "#{app_dir}/Gemfile.lock"
          Bundler.with_clean_env do
            so = Mixlib::ShellOut.new("bundle lock", env: { "BUNDLE_GEMFILE" => t.path })
            so.run_command
            so.error!
          end
          FileUtils.mv t.path, "#{app_dir}/Gemfile"
        end
      end
      "#{app_dir}/Gemfile"
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
      <<~E
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
      <<~EOS
        require "rubygems"

        begin
          # this works around rubygems/rubygems#2196 and can be removed in rubygems > 2.7.6
          require "rubygems/bundler_version_finder"
        rescue LoadError
          # probably means rubygems is too old or too new to have this class, and we don't care
        end

        # avoid appbundling if we are definitely running within a Bundler bundle.
        # most likely the check for defined?(Bundler) is enough since we don't require
        # bundler above, but just for paranoia's sake also we test to see if Bundler is
        # really doing its thing or not.
        unless defined?(Bundler) && Bundler.instance_variable_defined?("@load")
          ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil unless ENV["APPBUNDLER_ALLOW_RVM"] == "true"
          ::Gem.clear_paths
      EOS
    end

    def runtime_activate
      @runtime_activate ||= begin
        statements = runtime_dep_specs.map { |s| %Q{  gem "#{s.name}", "= #{s.version}"} }
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
      <<~E
          gem "#{name}", "= #{version}"
          gem "bundler" # force activation of bundler to avoid unresolved specs if there are multiple bundler versions
          spec = Gem::Specification.find_by_name("#{name}", "= #{version}")
        else
          spec = Gem::Specification.find_by_name("#{name}")
        end

        unless Gem::Specification.unresolved_deps.empty?
          $stderr.puts "APPBUNDLER WARNING: unresolved deps are CRITICAL performance bug, this MUST be fixed"
          Gem::Specification.reset
        end

        bin_file = spec.bin_file("#{bin_basename}")

        Kernel.load(bin_file)
      E
    end

    def executables
      spec = installed_spec
      spec.executables.map { |e| spec.bin_file(e) }
    end

    def runtime_dep_specs
      if external_lockfile?
        local_gemfile_lock_specs
      else
        add_dependencies_from(app_spec)
      end
    end

    def app_dependency_names
      @app_dependency_names ||= app_spec.dependencies.map(&:name)
    end

    def installed_spec
      Gem::Specification.find_by_name(app_spec.name, app_spec.version)
    end

    # In the 2-arg version of appbundler this loads the gemspec from the omnibus source
    # build directory (e.g. /var/cache/omnibus/src/chef/chef-14.10.9/chef.gemspec)
    #
    # For the 3-arg version of appbundler this loads the gemspec from the installed path
    # of the gem (e.g. /opt/chefdk/embedded/lib/ruby/gems/2.5.0/specifications/berkshelf-7.0.7.gemspec)
    #
    def app_spec
      if name.nil?
        Gem::Specification.load("#{bundle_path}/#{File.basename(@bundle_path)}.gemspec")
      else
        spec_for(name)
      end
    end

    # In the 2-arg version of appbundler this will be the the appdir of the gemspec in the
    # omnibus build directory (e.g. /var/cache/omnibus/src/chef/chef-14.10.9)
    #
    # In the 3-arg version of appbundler this will be the installed gems path
    # (e.g. /opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/berkshelf-7.0.7/)
    #
    def app_dir
      if name.nil?
        File.dirname(app_spec.loaded_from)
      else
        installed_spec.gem_dir
      end
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

      message = <<~MESSAGE
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
