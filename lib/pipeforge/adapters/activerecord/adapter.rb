# frozen_string_literal: true

# The entry file of the ActiveRecord adapter, required by the adapter registry. The version range is
# stated here because the gem does not declare ActiveRecord as a dependency.
gem "activerecord", ">= 8.0", "< 9"
require "active_record"
require_relative "target"
