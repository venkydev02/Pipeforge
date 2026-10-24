# frozen_string_literal: true

source "https://rubygems.org"

# The two gems of this repository. The adapter depends on the core.
gemspec path: "pipeforge"
gemspec path: "pipeforge-activerecord"

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "sqlite3", ">= 2.1" # an in-memory database for the adapter specs; never part of a gem
  gem "standard"
end
