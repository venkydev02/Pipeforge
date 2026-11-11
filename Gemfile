# frozen_string_literal: true

source "https://rubygems.org"

# The gem of this repository: the ActiveRecord adapter, with the core inside it. Another adapter
# gets its own gemspec at the root; add it here with `gemspec name: "<its name>"`.
gemspec

group :development, :test do
  gem "rspec", "~> 3.13"
  gem "sqlite3", ">= 2.1" # an in-memory database for the adapter specs; never part of a gem
  gem "pg", ">= 1.5" # the PostgreSQL driver for the adapter specs (DATABASE=postgresql); never part of a gem
  gem "standard"
end
