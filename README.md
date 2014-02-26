# Appbundler

Appbundler reads a Gemfile.lock and generates code with
`gem "some-dep", "= VERSION"` statements to lock the app's dependencies
to the versions selected by bundler. This code is used in binstubs for
the application so that running (e.g.) `chef-client` on the command line
activates the locked dependencies for `chef` before running the command.

This provides the following benefits:
* The application loads faster because rubygems is not resolving
  dependency constraints at runtime.
* The application runs with the same dependencies that it would if
  bundler was used, so we can test applications (that will be installed
  in an omnibus package) using the default bundler workflow.
* There's no need to `bundle exec` or patch the bundler runtime into the
  app.
* The app can load gems not included in the Gemfile/gemspec. Our use
  case for this is to load plugins (e.g., for knife and test kitchen).

