require 'appbundler/version'
require 'appbundler/app'
require 'mixlib/cli'

module Appbundler
  class CLI
    include Mixlib::CLI

    banner(<<-BANNER)
Usage: appbundler APPLICATION_DIR BINSTUB_DIR

  APPLICATION_DIR is the root directory to a working copy of your app
  BINSTUB_DIR is the directory where you want generated executables to be written

Your bundled application must already be gem installed.  Generated binstubs
will point to the gem, not your working copy.
BANNER

    option :version,
      :short => '-v',
      :long => '--version',
      :description => 'Show appbundler version',
      :boolean => true,
      :proc => lambda {|v| $stdout.puts("Appbundler Version: #{::Appbundler::VERSION}")},
      :exit => 0

    option :name,
      :long => '--name NAME',
      :description => 'name of gem to appbundle'

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

    attr_reader :gemfile_lock
    attr_reader :bin_path

    def initialize(argv)
      @argv = argv
      super()
    end

    def handle_options
      parse_options(argv)
    end

    def validate!
      if cli_arguments.size != 2
        usage_and_exit!
      else
        app_path_or_lock = File.expand_path(cli_arguments[0])
        if cli_arguments[0].end_with?(".lock")
          @gemfile_lock = File.expand_path(cli_arguments[0])
        else
          # If you didn't pass a .lock, you must have passed us the app path
          # under which Gemfile.lock and .bundle exist
          @gemfile_lock = "#{File.expand_path(cli_arguments[0])}/Gemfile.lock"
        end
        config[:name] ||= File.basename(File.dirname(gemfile_lock))
        @bin_path = File.expand_path(cli_arguments[1])
        verify_gemfile_lock
        verify_bin_path
        verify_gem_installed
      end
    end

    def verify_gemfile_lock
      if !File.directory?(File.dirname(gemfile_lock))
        err("APPLICATION_DIR `#{File.dirname(gemfile_lock)}' is not a directory or doesn't exist")
        usage_and_exit!
      elsif !File.exist?(gemfile_lock)
        err("#{gemfile_lock} does not exist")
        usage_and_exit!
      end
    end

    def verify_bin_path
      if !File.directory?(bin_path)
        err("BINSTUB_DIR `#{bin_path}' is not a directory or doesn't exist")
        usage_and_exit!
      end
    end

    def verify_gem_installed
      app = App.new(config[:name], gemfile_lock, bin_path)
      app.app_gemspec
    rescue Gem::LoadError
      err("Unable to find #{app.app_spec.name} #{app.app_spec.version} installed as a gem")
      err("You must install the top-level app as a gem before calling app-bundler")
      usage_and_exit!
    end

    def run
      app = App.new(config[:name], gemfile_lock, bin_path)
      created_stubs = app.write_executable_stubs
      created_stubs.each do |real_executable_path, stub_path|
        $stdout.puts "Generated binstub #{stub_path} => #{real_executable_path}"
      end
      app.copy_bundler_env
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
