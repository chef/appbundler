# Appbundler

[![Build Status Master](https://travis-ci.org/chef/appbundler.svg?branch=master)](https://travis-ci.org/chef/appbundler) [![Gem Version](https://badge.fury.io/rb/appbundler.svg)](https://badge.fury.io/rb/appbundler)

Appbundler reads a Gemfile.lock and generates code with `gem "some-dep", "= VERSION"` statements to lock the app's dependencies to the versions selected by bundler. This code is used in binstubs for the application so that running (e.g.) `chef-client` on the command line activates the locked dependencies for `chef` before running the command.

This provides the following benefits:

- The application loads faster because rubygems is not resolving dependency constraints at runtime.
- The application runs with the same dependencies that it would if bundler was used, so we can test applications (that will be installed in an omnibus package) using the default bundler workflow.
- There's no need to `bundle exec` or patch the bundler runtime into the app.
- The app can load gems not included in the Gemfile/gemspec. Our use case for this is to load plugins (e.g., for knife and test kitchen).
- A user can use rvm and still use the application (see below).
- The application is protected from installation of incompatible dependencies.

## Usage

Install via rubygems: `gem install appbundler` or clone this project and bundle install:

```shell
git clone https://github.com/chef/appbundler.git
cd appbundler
bundle install
```

Clone whatever project you want to appbundle somewhere else, and bundle install it:

```shell
mkdir ~/oc
cd ~/oc
git clone https://github.com/chef/chef.git
cd chef
bundle install
```

Create a bin directory where your bundled binstubs will live:

```shell
mkdir ~/appbundle-bin
# Add to your PATH if you like
```

Now you can app bundle your project (chef in our example):

```shell
bin/appbundler ~/oc/chef ~/appbundler-bin
```

Now you can run all of the app's executables with locked down deps:

```shell
~/appbunlder-bin/chef-client -v
```

## RVM

The generated binstubs explicitly disable rvm, so the above won't work if you're using rvm. This is intentional, because our use case is for omnibus applications where rvm's environment variables can break the embedded application by making ruby look for gems in rvm's gem repo.

## Contributing

For information on contributing to this project see <https://github.com/chef/chef/blob/master/CONTRIBUTING.md>

## License

- Copyright:: Copyright (c) 2014-2016 Chef Software, Inc.
- License:: Apache License, Version 2.0

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
