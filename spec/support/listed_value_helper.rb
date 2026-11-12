# frozen_string_literal: true

# Builds the values of the lists of distinct values, so a spec writes what it expects in one short line.
#
#   compatible_value(value: "30", count: 2, casted_to: 30)
#   incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)
module ListedValueHelper
  def compatible_value(value:, count:, casted_to:)
    Pipeforge::ColumnValueAnalyzer::CompatibleValue.new(value: value, count: count, casted_to: casted_to)
  end

  def incompatible_value(value:, count:, casted_to:, reason:)
    Pipeforge::ColumnValueAnalyzer::IncompatibleValue.new(
      value: value, count: count, casted_to: casted_to, reason: reason
    )
  end
end

RSpec.configure { |config| config.include ListedValueHelper }
