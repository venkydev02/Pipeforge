# frozen_string_literal: true

# Builds the mapped columns that the stages take from entries written as the consumer writes them. An entry may also
# carry the type and limits of its target column (+type+, +limit+, +unsigned+, +max_length+, +precision+, +scale+,
# +enum_values+); without them the target column is a string column with no limit.
#
#   mapped_columns_of("email" => {source_column: "Mail"}, "age" => {source_column: "Age", type: "integer", limit: 2})
module MappedColumnHelper
  TARGET_COLUMN_KEYS = %i[type limit unsigned max_length precision scale enum_values].freeze

  def mapped_columns_of(entries)
    entries.to_h do |target_column_name, entry|
      target_column = build_target_column(name: target_column_name, **entry.slice(*TARGET_COLUMN_KEYS))

      [target_column_name, Pipeforge::MappedColumn.from_entry(entry: entry, target_column: target_column)]
    end
  end
end

RSpec.configure { |config| config.include MappedColumnHelper }
