# x86-mingw32 Gemspec #
# coding: utf-8
gemspec = eval(IO.read(File.join(File.dirname(__FILE__), "example-app.gemspec")))
gemspec.platform = "ppc-aix5.1"
gemspec.executables += %w(exclude-me)

gemspec
