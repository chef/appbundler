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

Since this approach is deliberately inflexible against updating the appbundle pins in order to prevent transitive gem issues, it is instead possible and encouraged to
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

The alternative of trying to rebuild appbundled binstubs against an already built Chef-DK is documented here and is terrible idea:

https://github.com/chef/chef-dk/issues/1559#issuecomment-468103827

### BUG: you cannot install git gems using this method

This is simply a bug, although in practice it has turned into a feature.  You should never ship git checked out non production released gems to customers, so should
always be doing downstream gem releases in order to consume them in omnibus builds.  If this becomes a blocker this bug should just be fixed, but in practice this
has been a feature that has pushed development down the correct path.

### ChefDK transitive development gem Gemfile.locking madness

A sub-concern and design goal of the three-argument mega-Gemfile.lock appbundling feature is decoupling the purely development gem dependencies of sub-applications
from each other.  This feature should perhaps have been designed to be decoupled, but since the whole feature was written somewhat "tactically" (aka "code rage")
to deal with the complexity of the ChefDK builds and this feature is necessary there and came along for the ride.

The ChefDK Gemfile.lock is already hard enough to build as it is, and it does not include any of the development gems for its sub-applications (berkshelf, test-kitchen,
foodcritic, chefspec, etc, etc, etc).  It is already difficult enough to generate a sane single runtime closure across all the runtime gems.  The development gems used
to test berkshelf, etc should not be shipped in the omnibus build.  It is also an enormous amount of developer pain to keep the development gems consistent across all
of those projects, particularly when several of them are or historically were external to the company.

The result of that was a feature of the three argument version of appbundler where it takes the pins from the master ChefDK Gemfile.lock and merges those with the
gem statements in the Gemfile of the application (e.g. berkshelf) and then creates a combined Gemfile.lock which is written out in the gem directory.  So for ChefDK
3.8.14 the combined Gemfile.lock which is created for berkshelf is:

```
/opt/chefdk/embedded/lib/ruby/gems/2.5.0/gems/berkshelf-7.0.7/.appbundler-gemfile20190227-93370-84j06u.lock
```

That Gemfile.lock is only solved, but not installed at build time when appbundler runs (`bundle lock` not `bundle update/install`) so that the development gems are not
shipped.  In the testing phase of CI a `bundle install` is run against that so that all the development gems are installed on the testing box, all the pins in the
master Gemfile.lock will be applied (and those gems are already installed) and all the development gems of the app are installed with the constraints specified in
the Gemfile of the application.  The testing suite is then run via `bundle exec` against this Gemfile.lock via the `chef test` command.

This ensures that we test the app against every gem pin that we ship, while we allow dev pins between different apps to potentially conflict since those have meaning
only to the app in question.

Yes, this is complicated, but the alternative(s) would be to either bake every dev gem into the master Gemfile.lock and take the pain of reconciling otherwise meaningless
gem conficts, or to allow gems to float outside of the Gemfile.lock pins and to be guaranteed of shipping defects sooner or later due to not testing against exactly
what we ship.

For any consumers outside of ChefDK this Gemfile.lock being created can happily be entirely ignored and it won't hurt you at all.

### The meaning of the --without arg is not what you think

The --without argument to appbundler in the three argument version does not apply to the installed gemset (that is handled entirely by the one `bundle install` which
should be run against the master Gemfile.lock before appbundler runs) and it does not apply to the appbundled binstubs.

What the --without argument does is affect the rendered transitive gemfile.lock and is used to filter out unnecessary dependencies which conflict with the master
Gemfile.lock in the omnibus project.  A notable example of this was the github-changelog-generator gem which would pin gems (like `addressable`) to restrictive pins
and would not solve against the ChefDK master Gemfile.lock.  If github-changelog-generator was in a `:changelog` group it could then be excluded here, and it would not
conflict during generation of the transitive per-app gemfile.lock.

This argument does not affect the shipping apps in the omnibus build (that should be handled by `--without` arguments to the `bundle install`) or affect the generated
binstubs.  It is only in the codepath of the transitive lock generation and only affects the groups defined in the sub-application's Gemfile.

The `--without` argument was also added to the 3-argument version of appbundler specifically to handle this issue.  It is silently ignored on the 2-argument version.

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
~/appbundler-bin/chef-client -v
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
