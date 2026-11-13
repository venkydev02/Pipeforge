# frozen_string_literal: true

module Pipeforge
  # What a model adapter answers when it is asked to cast one value: whether the value can be cast and, when it can,
  # the value in its two representations. The two values mean something only when +castable+ is true.
  #   castable    whether the adapter can cast the value
  #   cast_value  what the model would load, a Ruby object; nil for the JSON null and when the value cannot be cast
  #   json_value  the cast value in plain JSON types; nil for the JSON null and when the value cannot be cast
  CastResult = Data.define(:castable, :cast_value, :json_value)

  # The answer for a text that cannot be cast.
  CastResult::NOT_CASTABLE = CastResult.new(castable: false, cast_value: nil, json_value: nil)
end
