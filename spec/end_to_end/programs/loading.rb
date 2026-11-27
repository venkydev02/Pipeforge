# frozen_string_literal: true

require "json"
require "pipeforge"

puts JSON.generate(loaded_from: $LOADED_FEATURES.grep(%r{/lib/pipeforge\.rb\z}).first)
