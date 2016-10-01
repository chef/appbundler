require "spec_helper"
require "tmpdir"
require "fileutils"
require "mixlib/shellout"
require "appbundler/app"

describe Appbundler do

  def all_specs
    @all_specs ||= []
  end

  def double_spec(name, version, dep_names)
    deps = dep_names.map { |n| double("Bundler::Dependency #{n}", :name => n.to_s) }
    source = double("Bundler::Source::Rubygems")
    spec = double("Bundler::LazySpecification '#{name}'", :name => name.to_s, :version => version, :dependencies => deps, :source => source)
    all_specs << spec
    spec
  end

  def shellout!(cmd)
    s = Mixlib::ShellOut.new(cmd, :env => { "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "APPBUNDLER_ALLOW_RVM" => "true" })
    s.run_command
    s.error!
    s
  end

  def target_bindir
    File.expand_path("../../test-tmp/bin", __FILE__)
  end

  context "given an app with multiple levels of dependencies" do

    let!(:second_level_dep_a_a) do
      double_spec(:second_level_dep_a_a, "2.1.0", [])
    end

    let!(:second_level_dep_shared) do
      double_spec(:second_level_dep_shared, "2.3.0", [])
    end

    let!(:second_level_dep_b_a) do
      double_spec(:second_level_dep_b_a, "2.2.0", [])
    end

    let!(:first_level_dep_a) do
      double_spec(:first_level_dep_a, "1.1.0", [:second_level_dep_a_a, :second_level_dep_shared])
    end

    let!(:first_level_dep_b) do
      double_spec(:first_level_dep_b, "1.2.0", [:second_level_dep_b_a, :second_level_dep_shared])
    end

    let!(:app_spec) do
      double_spec(:app, "1.0.0", [:first_level_dep_a, :first_level_dep_b])
    end

    let(:bin_path) { File.join(target_bindir, "foo") }

    let(:app_root) { "/opt/app/embedded/apps/app" }

    let(:app) do
      Appbundler::App.new(app_root, target_bindir, File.basename(app_root))
    end

    before do
      allow(app).to receive(:gemfile_lock_specs).and_return(all_specs)
    end

    it "finds the running ruby interpreter" do
      expect(app.ruby).to eq(Gem.ruby)
    end

    it "finds all runtime dependencies of the app" do
      # we want to find the minimum set of gems that we need to activate to run
      # the application. To do this, we look at the app's runtime deps and
      # recursively search through the list of gemspecs that we got from the
      # Gemfile.lock, collecting all the runtime deps. This should get us the
      # smallest possible "activate.rb" file that can launch the application
      # with locked gem versions.
      expect(app.runtime_dep_specs).to include(first_level_dep_a)
      expect(app.runtime_dep_specs).to include(first_level_dep_b)
      expect(app.runtime_dep_specs).to include(second_level_dep_a_a)
      expect(app.runtime_dep_specs).to include(second_level_dep_b_a)
      expect(app.runtime_dep_specs).to include(second_level_dep_shared)
      expect(app.runtime_dep_specs.select { |s| s == second_level_dep_shared }.size).to eq(1)
    end

    it "generates gem activation code for the app" do
      # this is code with a bunch of gem "foo", "= X.Y.Z" statements. The top
      # level application is _not_ included in this, it's added to the load
      # path instead.
      expect(app.runtime_activate).to include(%q{gem "first_level_dep_a", "= 1.1.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_a_a", "= 2.1.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_shared", "= 2.3.0"})
      expect(app.runtime_activate).to include(%q{gem "first_level_dep_b", "= 1.2.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_b_a", "= 2.2.0"})
      expect(app.runtime_activate).to_not include(%q{gem "app"})
    end

    it "locks the main app's gem via rubygems, and loads the proper binary" do
      expected_loading_code = <<-CODE
gem "app", "= 1.0.0"

spec = Gem::Specification.find_by_name("app", "= 1.0.0")
bin_file = spec.bin_file("foo")

Kernel.load(bin_file)
CODE
      expect(app.load_statement_for(bin_path)).to eq(expected_loading_code)
    end

    it "generates code to override GEM_HOME and GEM_PATH (e.g., rvm)" do
      expected = <<-EOS
ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil unless ENV["APPBUNDLER_ALLOW_RVM"] == "true"
require "rubygems"
::Gem.clear_paths
EOS

      expect(app.env_sanitizer).to eq(expected)
      expect(app.runtime_activate).to include(expected)
    end

    context "on windows" do

      let(:target_bindir) { "C:/opscode/chef/bin" }

      before do
        allow(app).to receive(:ruby).and_return("C:/opscode/chef/embedded/bin/ruby.exe")
      end

      it "computes the relative path to ruby" do
        expect(app.ruby_relative_path).to eq("../embedded/bin/ruby.exe")
      end

      it "generates batchfile stub code" do
        expected_batch_code = <<-E
@ECHO OFF
"%~dp0\\..\\embedded\\bin\\ruby.exe" "%~dpn0" %*
E
        expect(app.batchfile_stub).to eq(expected_batch_code)
      end

    end

    context "when there are git-sourced gems in the Gemfile.lock" do

      let!(:second_level_dep_b_a) do
        source = double("Bundler::Source::Git")
        allow(source).to receive(:kind_of?).with(Bundler::Source::Git).and_return(true)
        spec = double_spec(:second_level_dep_b_a, "2.2.0", [])
        allow(spec).to receive(:source).and_return(source)
        spec
      end

      # Ensure that the behavior we emulate in our stubs is correct:
      it "sanity checks rubygems behavior" do
        expect { Gem::Specification.find_by_name("there-is-no-such-gem-named-this", "= 999.999.999") }.
          to raise_error(Gem::LoadError)
      end

      context "and the gems are not accessible by rubygems" do

        before do
          allow(Gem::Specification).to receive(:find_by_name).with("second_level_dep_b_a", "= 2.2.0").and_raise(Gem::LoadError)
        end

        it "raises an error validating gem accessibility" do
          expect { app.verify_deps_are_accessible! }.to raise_error(Appbundler::InaccessibleGemsInLockfile)
        end

      end

      context "and the gems are accessible by rubygems" do

        before do
          allow(Gem::Specification).to receive(:find_by_name).with("second_level_dep_b_a", "= 2.2.0").and_return(true)
        end

        it "raises an error validating gem accessibility" do
          expect { app.verify_deps_are_accessible! }.to_not raise_error
        end

      end

    end

  end

  context "when created with the example application" do
    FIXTURES_PATH = File.expand_path("../../fixtures/", __FILE__).freeze

    APP_ROOT = File.join(FIXTURES_PATH, "appbundler-example-app").freeze

    let(:app_root) { APP_ROOT }

    let(:app) do
      Appbundler::App.new(APP_ROOT, target_bindir, File.basename(APP_ROOT))
    end

    before(:all) do
      Dir.chdir(APP_ROOT) do
        if windows?
          FileUtils.cp("Gemfile.lock.windows", "Gemfile.lock")
        else
          FileUtils.cp("Gemfile.lock.unix", "Gemfile.lock")
        end
        shellout!("bundle install")
        shellout!("gem build appbundler-example-app.gemspec")
        shellout!("gem install appbundler-example-app-1.0.0.gem")
        Gem.clear_paths
      end
    end

    before do
      FileUtils.rm_rf(target_bindir) if File.exist?(target_bindir)
      FileUtils.mkdir_p(target_bindir)
    end

    after(:all) do
      shellout!("gem uninstall appbundler-example-app -a -q -x")
      FileUtils.rm_rf(target_bindir) if File.exist?(target_bindir)
      FileUtils.rm(File.join(APP_ROOT, "Gemfile.lock"))
    end

    it "initializes ok" do
      app
    end

    it "names the app using the directory basename" do
      expect(app.name).to eq("appbundler-example-app")
    end

    it "lists the app's dependencies" do
      # only runtime deps
      expect(app.app_dependency_names).to eq(["chef"])
    end

    it "generates runtime activation code for the app" do
      expected_gem_activates = if windows?
                                 <<-E
ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil unless ENV["APPBUNDLER_ALLOW_RVM"] == "true"
require "rubygems"
::Gem.clear_paths

gem "chef", "= 12.4.1"
gem "chef-config", "= 12.4.1"
gem "mixlib-config", "= 2.2.1"
gem "mixlib-shellout", "= 2.2.0"
gem "win32-process", "= 0.7.5"
gem "ffi", "= 1.9.10"
gem "chef-zero", "= 4.3.0"
gem "ffi-yajl", "= 2.2.2"
gem "libyajl2", "= 1.2.0"
gem "hashie", "= 2.1.2"
gem "mixlib-log", "= 1.6.0"
gem "rack", "= 1.6.4"
gem "uuidtools", "= 2.1.5"
gem "diff-lcs", "= 1.2.5"
gem "erubis", "= 2.7.0"
gem "highline", "= 1.7.3"
gem "mixlib-authentication", "= 1.3.0"
gem "mixlib-cli", "= 1.5.0"
gem "net-ssh", "= 2.9.2"
gem "net-ssh-multi", "= 1.2.1"
gem "net-ssh-gateway", "= 1.2.0"
gem "ohai", "= 8.5.1"
gem "ipaddress", "= 0.8.0"
gem "mime-types", "= 2.6.1"
gem "rake", "= 10.1.1"
gem "systemu", "= 2.6.5"
gem "wmi-lite", "= 1.0.0"
gem "plist", "= 3.1.0"
gem "pry", "= 0.9.12.6"
gem "coderay", "= 1.1.0"
gem "method_source", "= 0.8.2"
gem "slop", "= 3.4.7"
gem "win32console", "= 1.3.2"
gem "rspec-core", "= 3.3.2"
gem "rspec-support", "= 3.3.0"
gem "rspec-expectations", "= 3.3.1"
gem "rspec-mocks", "= 3.3.2"
gem "rspec_junit_formatter", "= 0.2.3"
gem "builder", "= 3.2.2"
gem "serverspec", "= 2.23.1"
gem "multi_json", "= 1.11.2"
gem "rspec", "= 3.3.0"
gem "rspec-its", "= 1.2.0"
gem "specinfra", "= 2.43.3"
gem "net-scp", "= 1.2.1"
gem "net-telnet", "= 0.1.1"
gem "sfl", "= 2.2"
gem "syslog-logger", "= 1.6.8"
gem "win32-api", "= 1.5.3"
gem "win32-dir", "= 0.5.0"
gem "win32-event", "= 0.6.1"
gem "win32-ipc", "= 0.6.6"
gem "win32-eventlog", "= 0.6.3"
gem "win32-mmap", "= 0.4.1"
gem "win32-mutex", "= 0.4.2"
gem "win32-service", "= 0.8.6"
gem "windows-api", "= 0.4.4"
gem "windows-pr", "= 1.2.4"
E
                               else
                                 <<-E
ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil unless ENV["APPBUNDLER_ALLOW_RVM"] == "true"
require "rubygems"
::Gem.clear_paths

gem "chef", "= 12.4.1"
gem "chef-config", "= 12.4.1"
gem "mixlib-config", "= 2.2.1"
gem "mixlib-shellout", "= 2.2.0"
gem "chef-zero", "= 4.3.0"
gem "ffi-yajl", "= 2.2.2"
gem "libyajl2", "= 1.2.0"
gem "hashie", "= 2.1.2"
gem "mixlib-log", "= 1.6.0"
gem "rack", "= 1.6.4"
gem "uuidtools", "= 2.1.5"
gem "diff-lcs", "= 1.2.5"
gem "erubis", "= 2.7.0"
gem "highline", "= 1.7.3"
gem "mixlib-authentication", "= 1.3.0"
gem "mixlib-cli", "= 1.5.0"
gem "net-ssh", "= 2.9.2"
gem "net-ssh-multi", "= 1.2.1"
gem "net-ssh-gateway", "= 1.2.0"
gem "ohai", "= 8.5.1"
gem "ffi", "= 1.9.10"
gem "ipaddress", "= 0.8.0"
gem "mime-types", "= 2.6.1"
gem "rake", "= 10.1.1"
gem "systemu", "= 2.6.5"
gem "wmi-lite", "= 1.0.0"
gem "plist", "= 3.1.0"
gem "pry", "= 0.9.12.6"
gem "coderay", "= 1.1.0"
gem "method_source", "= 0.8.2"
gem "slop", "= 3.4.7"
gem "rspec-core", "= 3.3.2"
gem "rspec-support", "= 3.3.0"
gem "rspec-expectations", "= 3.3.1"
gem "rspec-mocks", "= 3.3.2"
gem "rspec_junit_formatter", "= 0.2.3"
gem "builder", "= 3.2.2"
gem "serverspec", "= 2.23.1"
gem "multi_json", "= 1.11.2"
gem "rspec", "= 3.3.0"
gem "rspec-its", "= 1.2.0"
gem "specinfra", "= 2.43.3"
gem "net-scp", "= 1.2.1"
gem "net-telnet", "= 0.1.1"
gem "sfl", "= 2.2"
gem "syslog-logger", "= 1.6.8"
E
                               end
      expect(app.runtime_activate).to include(expected_gem_activates)
    end

    it "lists the app's executables" do
      spec = Gem::Specification.find_by_name("appbundler-example-app", "= 1.0.0")
      expected_executables = %w{app-binary-1 app-binary-2}.map do |basename|
        File.join(spec.gem_dir, "/bin", basename)
      end
      expect(app.executables).to match_array(expected_executables)
    end

    it "generates an executable 'stub' for an executable in the app" do
      app_binary_1_path = app.executables.grep(/app\-binary\-1/).first
      executable_content = app.binstub(app_binary_1_path)

      shebang = executable_content.lines.first
      expect(shebang).to match(/^\#\!/)
      expect(shebang).to include(Gem.ruby)

      expect(executable_content).to include(app.runtime_activate)

      load_binary = executable_content.lines.to_a.last

      expected_load_path = %Q{Kernel.load(bin_file)\n}

      expect(load_binary).to eq(expected_load_path)
    end

    it "generates executable stubs for all executables in the app" do
      app.verify_deps_are_accessible!
      app.write_executable_stubs
      binary_1 = File.join(target_bindir, "app-binary-1")
      binary_2 = File.join(target_bindir, "app-binary-2")
      expect(File.exist?(binary_1)).to be(true)
      expect(File.exist?(binary_2)).to be(true)
      expect(File.executable?(binary_1) || File.exists?(binary_1 + ".bat")).to be(true)
      expect(File.executable?(binary_1) || File.exists?(binary_1 + ".bat")).to be(true)
      expect(shellout!(binary_1).stdout.strip).to eq("binary 1 ran")
      expect(shellout!(binary_2).stdout.strip).to eq("binary 2 ran")
    end

    it "copies over Gemfile.lock to the gem directory" do
      spec = Gem::Specification.find_by_name("appbundler-example-app", "= 1.0.0")
      gem_path = spec.gem_dir
      app.copy_bundler_env
      expect(File.exists?(File.join(gem_path, "Gemfile.lock"))).to be(true)
    end

    it "copies over .bundler to the gem directory" do
      spec = Gem::Specification.find_by_name("appbundler-example-app", "= 1.0.0")
      gem_path = spec.gem_dir
      app.copy_bundler_env
      expect(File.directory?(File.join(gem_path, ".bundle"))).to be(true)
      expect(File.exists?(File.join(gem_path, ".bundle/config"))).to be(true)
    end
    context "and the executable is symlinked to a different directory", :not_supported_on_windows do

      let(:symlinks_root_dir) do
        Dir.mktmpdir
      end

      let(:symlinks_bin_dir) do
        d = File.join(symlinks_root_dir, "bin")
        FileUtils.mkdir(d)
        d
      end

      let(:binary_symlinked_path) { File.join(symlinks_bin_dir, "app-binary-1") }

      let(:binary_orignal_path) { File.join(target_bindir, "app-binary-1") }

      before do
        app.write_executable_stubs
        FileUtils.ln_s(binary_orignal_path, binary_symlinked_path)
      end

      after do
        FileUtils.rm_rf(symlinks_root_dir)
      end

      it "correctly runs the executable via the symlinked executable" do
        expect(shellout!(binary_symlinked_path).stdout).to eq("binary 1 ran\n")
      end

    end

    context "on windows" do

      let(:expected_ruby_relpath) do
        app.ruby_relative_path.tr("/", '\\')
      end

      let(:expected_batch_code) do
        <<-E
@ECHO OFF
"%~dp0\\#{expected_ruby_relpath}" "%~dpn0" %*
E
      end

      before do
        stub_const("RUBY_PLATFORM", "mingw")
      end

      it "creates a batchfile wrapper for each executable" do
        app.write_executable_stubs
        binary_1 = File.join(target_bindir, "app-binary-1.bat")
        binary_2 = File.join(target_bindir, "app-binary-2.bat")
        expect(File.exist?(binary_1)).to be(true)
        expect(File.exist?(binary_2)).to be(true)
        expect(IO.read(binary_1)).to eq(expected_batch_code)
        expect(IO.read(binary_2)).to eq(expected_batch_code)
      end

    end

  end

end
