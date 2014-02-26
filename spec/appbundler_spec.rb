require 'spec_helper'
require 'appbundler'

describe Appbundler do

  it "loads" do
    true
  end

  def all_specs
    @all_specs ||= []
  end

  def double_spec(name, dep_names)
    deps = dep_names.map {|n| double("Bundler::Dependency #{n}", :name => n.to_s) }
    spec = double("Bundler::LazySpecification '#{name}'", :name => name.to_s, :dependencies => deps)
    all_specs << spec
    spec
  end

  context "given an app with multiple levels of dependencies" do

    let!(:second_level_dep_a_a) do
      double_spec(:second_level_dep_a_a, [])
    end

    let!(:second_level_dep_shared) do
      double_spec(:second_level_dep_shared, [])
    end

    let!(:second_level_dep_b_a) do
      double_spec(:second_level_dep_b_a, [])
    end

    let!(:first_level_dep_a) do
      double_spec(:first_level_dep_a, [:second_level_dep_a_a, :second_level_dep_shared])
    end

    let!(:first_level_dep_b) do
      double_spec(:first_level_dep_b, [:second_level_dep_b_a, :second_level_dep_shared])
    end

    let!(:app_spec) do
      double_spec(:app, [:first_level_dep_a, :first_level_dep_b])
    end

    let(:app) do
      a = Appbundler::App.new
      a.name = "app"
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

    it "generates an activation file for the app" do
      pending

      # this is a file with a bunch of gem "foo", "= X.Y.Z" statements. The
      # code spike doesn't properly account for loading the actual app from a
      # local checkout. Need to see how bundler activates the "app gem" and
      # borrow the logic.
    end

    it "finds all the dependencies of the app" do
      pending

      # this would be used if we want a "test-activate.rb" to load all the
      # app's dependencies, runtime and dev. It should include everything the
      # gemfile.lock says to include.
    end

  end

end
