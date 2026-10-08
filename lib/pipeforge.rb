# frozen_string_literal: true

require "active_record"
require_relative "pipeforge/version"

# Relational data migration engine. See docs/architecture/overview.md.
module Pipeforge
  class Error < StandardError; end
end
