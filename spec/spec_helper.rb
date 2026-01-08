# Copyright (C) 2017-2025 Progress Software Corporation and/or its subsidiaries or affiliates. All Rights Reserved.
def windows?
  !!(RUBY_PLATFORM =~ /mswin|mingw|windows/)
end

RSpec.configure do |c|
  c.filter_run focus: true
  c.run_all_when_everything_filtered = true
  c.filter_run_excluding(not_supported_on_windows: true) if windows?
end
