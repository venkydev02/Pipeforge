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

      [target_column_name, Pipeforge::ResolvedMappedColumn.from_entry(entry: entry, target_column: target_column)]
    end
  end
end

RSpec.configure { |config| config.include ResolvedMappedColumnHelper }
