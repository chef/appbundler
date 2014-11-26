require 'appbundler/version'
require 'appbundler/config'
require 'appbundler/app'
require 'mixlib/cli'

module Appbundler
  class CLI
    include Mixlib::CLI

    banner(<<-BANNER)
Usage: appbundler APPLICATION_DIR BINSTUB_DIR

  APPLICATION_DIR is the root directory of your app
  BINSTUB_DIR is the directory where you want generated executables to be written
BANNER

    attr_reader :argv

    attr_reader :app_path
    attr_reader :bin_path


    option :version,
      :short => '-v',
      :long => '--version',
      :description => 'Show appbundler version',
      :boolean => true,
      :proc => lambda {|v| $stdout.puts("Appbundler Version: #{::Appbundler::VERSION}")},
      :exit => 0

    option :help,
      :short => "-h",
      :long => "--help",
      :description => "Show this message",
      :on => :tail,
      :boolean => true,
      :show_options => true,
      :exit => 0

    option :exclude,
      :long => '--exclude BIN',
      :description => 'Binary to exclude',
      :proc => lambda {|bin| Appbundler::Config.exclusions << bin}

    def self.run(argv)
      cli = new(argv)
      cli.handle_options
      cli.validate!
      cli.run
    end

    def initialize(argv)
      @argv = argv
      super()
    end

    def handle_options
      parse_options(@argv)
    end

    def validate!
      if cli_arguments.size != 2
        usage_and_exit!
      else
        @app_path = File.expand_path(cli_arguments[0])
        @bin_path = File.expand_path(cli_arguments[1])
        verify_app_path
        verify_bin_path
        verify_excludes
      end
    end

    def verify_app_path
      if !File.directory?(app_path)
        err("APPLICATION_DIR `#{app_path}' is not a directory or doesn't exist")
        usage_and_exit!
      elsif !File.exist?(File.join(app_path, "Gemfile.lock"))
        err("APPLICATION_DIR does not contain require Gemfile.lock")
        usage_and_exit!
      end
    end

    def verify_bin_path
      if !File.directory?(bin_path)
        err("BINSTUB_DIR `#{bin_path}' is not a directory or doesn't exist")
        usage_and_exit!
      end
    end

    def verify_excludes
      missing_bins = ::Appbundler::Config.exclusions.reject do |bin|
        File.exists?(File.join(app_path, 'bin', bin))
      end
      if not missing_bins.empty?
        missing_bins.each do |bin|
          err("APPLICATION_DIR/bin does not contain #{bin}")
        end
        usage_and_exit!
      end
    end

    def run
      created_stubs = App.new(app_path, bin_path).write_executable_stubs
      created_stubs.each do |real_executable_path, stub_path|
        $stdout.puts "Generated binstub #{stub_path} => #{real_executable_path}"
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
