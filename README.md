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

## ChefDK Usage

### Primary Design

The 3-argument form of appbundler is used in ChefDK (and should be used elsewhere) to pin multiple apps in the same omnibus install against one master Gemfile.lock.

When used this way appbundler takes three arguments:  the lockdir containing the main Gemfile.lock of the omnibus package, the bindir to install the binstubs to, and
the gem to appbundle.  In this way all the gems in the omnibus app should be appbundled against the same Gemfile.lock.  The omnibus software definition should bundle install
this Gemfile.lock prior to appbundling.

This will pin all of the bunstubs against every gem in the referenced Gemfile.lock.  This is equivalent and identical behavior to copying the Gemfile.lock to a
directory, running `bundle install` and then using `bundle exec` to launch any of the applications.  The only major difference is that the appbundle pins apply only to the
gems in the gemfile, while `bundle exec` will prevent any other external gems from being able to be loaded into the gemset.

The design goals are brutally simple -- replicating the effects of `bundle exec` against the master Gemfile.lock while allowing the gemset to be open.

### Preventing duplicate gems

One of the features of this approach are that it becomes guaranteed that there will be no duplicate gems.  In order for this to be true, however, all gems must be installed
only from the master Gemfile.lock (and only one version of a gem may appear in any valid Gemfile.lock).  If the omnibus projects does anything other than a single
`bundle install` against the master Gemfile.lock to install gems then there likely will be multiple gems installed.  IF the apps are appbundled correctly, however, this
will still not have any negative effects since all runtime gems are pinned.

Historically this issue has caused problems due to transitive dep issues causing different version of gems to be loaded based on which application was launched which would
later cause gem conflicts. It also simply caused user confusion.

### Preventing transitive gem issues

Given that ChefDK and most chef applications are open pluggable architectures any arbitrary gems may be loaded lazily at runtime long after the initial application has
launched.  The classic example of the kind of bug which occurs is external third-party knife-plugins which require gems that are not part of the chef-client/knife
gemset but which collide with the explict pins on berkshelf.  Since the command line invocation is `knife` the berkshelf gem pins were not applied up front, a lazy
load of the transitive gem was then executed which activated the latest version which was installed with the knife plugin, then berkshelf was activated which would
conflict due to a pessimistic pin in the berksehlf gemspec itself.

While this is a complicated set of events it was actually fairly commonly reported:

* https://github.com/chef/chef-dk/issues/1187
* https://github.com/chef/chef-dk/issues/281
* https://github.com/berkshelf/berkshelf/issues/1357
* https://stackoverflow.com/questions/31906153/chef-gemconflicterror-when-running-knife-bootstrap-windows
* https://github.com/chef/chef-dk/issues/603

The aggressive pinning of all gems in the Gemfile.lock against all apps in the Gemfile.lock have eliminated this complaint entirely.

### Appbundler and bundler coexistance

Since this approach is deliberately inflexible against updating the sppbundle pins in order to prevent transitive gem issues, it is instead possible and encouraged to
use Gemfile and bundler as usual.  If the binstubs detect that they are running from within bundler against an external Gemfile.lock they do not apply any pins
at all.

* https://github.com/chef/chef-dk/issues/1547
* https://github.com/chef/appbundler/pull/43

### Encouraged use of bundler by end users

The ability to patch an existing omnibus built package is not well supported.  What it would result in would be the user taking the application Gemfile and
patching it manually and producing a Gemfile.lock which was solved correctly and then running appubndler against that Gemfile.lock for all the applications in
the bundle.  The difficult part is obviously the user updating the Gemfile.lock which cannot be automated and ultimately boils down to the process that we
use internally to solve gem conflict problems and produce the Gemfile.lock as an acutal product by experts.

What is vastly simpler is to create Gemfiles and use bundler to solve specific issues.  In particular the problem of new ChefDK (e.g. ChefDK 3.x) managing
old chef-client (e.g. 12.x) can be solved via bundler in one specific case.  For knife and test-kitchen the bootstrapped version of chef-client on the target
host is entirely configurable in those tools.  The only major conflict is in the use of chefspec.  For that use case, users are encouraged to create a much
more simplified Gemfile with a pinned chef version, berkshelf and chefspec and to `bundle install` and `bundle exec rspec` against the Gemfile.lock.  This
targeted use of bundler is vastly simpler than attempting to create a Chef-12 "version" of ChefDK 3.x.

### Developers should call `--without` on the `bundle install`

Appbundling in this form does not support `--without` nor should it.  That should be applied to the `bundle install` command that is used to install the gemset, not
to the appbundle command itself.  If there are development dependencies in the Gemfile.lock those should not be installed, much less appbundled.  Trying to exclude
installed gemsets from an appbundle is going down the road of trying to defeat the purpose of the design which will lead to transitive Gemfile.lock problems.

### BUG: you cannot install git gems using this method

This is simply a bug, although in practice it has turned into a feature.  You should never ship git checked out non production released gems to customers, so should
always be doing downstream gem releases in order to consume them in omnibus builds.  If this becomes a blocker this bug should just be fixed, but in practice this
has been a feature that has pushed development down the correct path.

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
