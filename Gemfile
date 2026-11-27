# frozen_string_literal: true

source "https://rubygems.org"

# The gem of this repository. It does not declare a database library, so the development group lists the ones
# its adapters need.
gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "activerecord", ">= 8.0", "< 9" # the library of the ActiveRecord adapter; never part of the gem
  gem "pg", ">= 1.5" # the PostgreSQL driver for the adapter specs; never part of a gem
  gem "standard"
end
