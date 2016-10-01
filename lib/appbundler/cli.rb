require "appbundler/version"
require "appbundler/app"
require "mixlib/cli"

module Appbundler
  class CLI
    include Mixlib::CLI

    banner(<<-BANNER)
* appbundler #{VERSION} *

Usage: appbundler BUNDLE_DIR BINSTUB_DIR [GEM_NAME] [GEM_NAME] ...

  BUNDLE_DIR is the root directory to the bundle containing your app
  BINSTUB_DIR is the directory where you want generated executables to be written
  GEM_NAME is the name of a gem you want to appbundle. Default is the directory name
           of BUNDLE_DIR (e.g. /src/chef -> chef)

Your bundled application must already be gem installed.  Generated binstubs
will point to the gem, not your working copy.
BANNER

    option :version,
      :short => "-v",
      :long => "--version",
      :description => "Show appbundler version",
      :boolean => true,
      :proc => lambda { |v| $stdout.puts("Appbundler Version: #{::Appbundler::VERSION}") },
      :exit => 0

    option :help,
      :short => "-h",
      :long => "--help",
      :description => "Show this message",
      :on => :tail,
      :boolean => true,
      :show_options => true,
      :exit => 0

    def self.run(argv)
      cli = new(argv)
      cli.handle_options
      cli.validate!
      cli.run
    end

    attr_reader :argv

    attr_reader :bundle_path
    attr_reader :bin_path
    attr_reader :gems

    def initialize(argv)
      @argv = argv
      super()
    end

    def handle_options
      parse_options(@argv)
    end

    def validate!
      if cli_arguments.size < 2
        usage_and_exit!
      else
        @bundle_path = File.expand_path(cli_arguments[0])
        @bin_path = File.expand_path(cli_arguments[1])
        @gems = cli_arguments[2..-1]
        @gems = [ File.basename(@bundle_path) ] if @gems.empty?
        verify_bundle_path
        verify_bin_path
        verify_gems_installed
        verify_deps_are_accessible
      end
    end

    def verify_bundle_path
      if !File.directory?(bundle_path)
        err("BUNDLE_DIR `#{bundle_path}' is not a directory or doesn't exist")
        usage_and_exit!
      elsif !File.exist?(File.join(bundle_path, "Gemfile.lock"))
        err("BUNDLE_DIR does not contain required Gemfile.lock")
        usage_and_exit!
      end
    end

    def verify_bin_path
      if !File.directory?(bin_path)
        err("BINSTUB_DIR `#{bin_path}' is not a directory or doesn't exist")
        usage_and_exit!
      end
    end

    def verify_gems_installed
      gems.each do |g|
        begin
          app = App.new(bundle_path, bin_path, g)
          app.app_gemspec
        rescue Gem::LoadError
          err("Unable to find #{app.app_spec.name} #{app.app_spec.version} installed as a gem")
          err("You must install the top-level app as a gem before calling app-bundler")
          usage_and_exit!
        end
      end
    end

    def verify_deps_are_accessible
      gems.each do |g|
        begin
          app = App.new(bundle_path, bin_path, g)
          app.verify_deps_are_accessible!
        rescue InaccessibleGemsInLockfile => e
          err(e.message)
          exit 1
        end
      end
    end

    def run
      gems.each do |g|
        app = App.new(bundle_path, bin_path, g)
        created_stubs = app.write_executable_stubs
        created_stubs.each do |real_executable_path, stub_path|
          $stdout.puts "Generated binstub #{stub_path} => #{real_executable_path}"
        end
        app.copy_bundler_env
      end
    end

    def err(message)
      $stderr.print("#{message}\n")
    end

    def usage_and_exit!
      err(banner)
      exit 1
    end
  end
end
