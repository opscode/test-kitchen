# -*- encoding: utf-8 -*-
source "https://rubygems.org"
gemspec
gem "rack", "< 2.0"

gem "train", "~> 0.22"

group :integration do
  gem "berkshelf", "~> 4.3"
  gem "kitchen-inspec", "~> 0.15.1"
end

group :test do
  gem "codeclimate-test-reporter", "~> 1.0", ">= 1.0.3", require: nil
end

gem "mixlib-install", github: "chef/mixlib-install"
