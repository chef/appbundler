require 'spec_helper'
require 'appbundler'

describe Appbundler do

  def all_specs
    @all_specs ||= []
  end

  def double_spec(name, version, dep_names)
    deps = dep_names.map {|n| double("Bundler::Dependency #{n}", :name => n.to_s) }
    spec = double("Bundler::LazySpecification '#{name}'", :name => name.to_s, :version => version, :dependencies => deps)
    all_specs << spec
    spec
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

    let(:app_root) { "/opt/app/embedded/apps/app" }

    let(:app) do
      a = Appbundler::App.new
      a.app_root = app_root
      a
    end

    before do
      app.stub(:gemfile_lock_specs).and_return(all_specs)
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
      expect(app.runtime_dep_specs.select {|s| s == second_level_dep_shared}).to have(1).item
    end

    it "generates gem activation code for the app" do
      # this is code with a bunch of gem "foo", "= X.Y.Z" statements. The
      # code spike doesn't properly account for loading the actual app from a
      # local checkout. Need to see how bundler activates the "app gem" and
      # borrow the logic.
      expect(app.runtime_activate).to include(%q{gem "first_level_dep_a", "= 1.1.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_a_a", "= 2.1.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_shared", "= 2.3.0"})
      expect(app.runtime_activate).to include(%q{gem "first_level_dep_b", "= 1.2.0"})
      expect(app.runtime_activate).to include(%q{gem "second_level_dep_b_a", "= 2.2.0"})
    end

    it "adds the app code to the load path" do
      expect(app.runtime_activate).to include('$:.unshift "/opt/app/embedded/apps/app/lib"')
    end

    it "generates code to override GEM_HOME and GEM_PATH (e.g., rvm)" do
      expected = %Q{ENV["GEM_HOME"] = ENV["GEM_PATH"] = nil}
      expect(app.env_sanitizer).to eq(expected)
      expect(app.runtime_activate).to include(expected)
    end

  end

end
