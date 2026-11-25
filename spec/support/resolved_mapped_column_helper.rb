# frozen_string_literal: true

# Builds the mapped columns that the stages take from entries written as the consumer writes them. An entry may also
# carry the type and limits of its target column (+type+, +limit+, +is_signed+, +max_length+, +precision+, +scale+,
# +enum_labels+); without them the target column is a string column with no limit.
#
#   resolve_mapped_columns("email" => {source_column_name: "Mail"}, "age" => {source_column_name: "Age", type: "integer", limit: 2})
module ResolvedMappedColumnHelper
  TARGET_COLUMN_KEYS = %i[type limit is_signed max_length precision scale enum_labels].freeze

  def resolve_mapped_columns(entries)
    entries.to_h do |target_column_name, entry|
      target_column = build_target_column(name: target_column_name, **entry.slice(*TARGET_COLUMN_KEYS))

      [target_column_name, resolved_mapped_column_of(entry: entry, target_column: target_column)]
    end
  end

  # The same, for the target columns a spec built itself (with build_target_column): each entry is given the column of its name.
  def resolve_mapped_columns_of(target_columns:, mapped_columns:)
    resolved_mapped_columns = {}

    mapped_columns.each do |target_column_name, entry|
      target_column = target_columns.find { |candidate| candidate.name == target_column_name }
      resolved_mapped_columns[target_column_name] = resolved_mapped_column_of(entry: entry, target_column: target_column)
    end

    resolved_mapped_columns
  end

  def resolved_mapped_column_of(entry:, target_column:)
    Pipeforge::ResolvedMappedColumn.new(
      source_column_name: entry.fetch(:source_column_name), value_mapping: entry.fetch(:value_mapping, {}),
      target_column: target_column
    )
  end
end

RSpec.configure { |config| config.include ResolvedMappedColumnHelper }
