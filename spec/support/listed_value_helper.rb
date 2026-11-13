# frozen_string_literal: true

# Builds the values of the lists of distinct values, so a spec writes what it expects in one short line.
#
#   compatible_value(value: "30", count: 2, casted_to: 30)
#   compatible_value(value: "Active", count: 1, mapping_applied: true, mapped_value: "1", casted_to: 1)
#   incompatible_value(value: "x", count: 1, casted_to: nil, reason: :value_not_castable)
#
# A value is not mapped, and its mapped value is the value itself, unless the example says otherwise.
module ListedValueHelper
  def compatible_value(value:, count:, casted_to:, mapping_applied: false, mapped_value: value)
    Pipeforge::ColumnValueAnalyzer::CompatibleValue.new(
      value: value, count: count, mapping_applied: mapping_applied, mapped_value: mapped_value, casted_to: casted_to
    )
  end

  def incompatible_value(value:, count:, casted_to:, reason:, mapping_applied: false, mapped_value: value)
    Pipeforge::ColumnValueAnalyzer::IncompatibleValue.new(
      value: value, count: count, mapping_applied: mapping_applied, mapped_value: mapped_value,
      casted_to: casted_to, reason: reason
    )
  end
end

RSpec.configure { |config| config.include ListedValueHelper }
