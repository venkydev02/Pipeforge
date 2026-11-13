# frozen_string_literal: true

module Pipeforge
  module ColumnValueAnalyzer
    # A distinct text of the file that the column accepts, with how many times it appears.
    #   value            the text as the file has it
    #   count            how many times the text appears
    #   mapping_applied  whether the value mapping has an entry for the text, and it was applied
    #   mapped_value     what is loaded for the text: what the value mapping gives, in its own shape, or the text
    #                    itself when the mapping has no entry for it
    #   casted_to        the mapped value read as the column's type, in plain JSON types; nil for the JSON null
    CompatibleValue = Data.define(:value, :count, :mapping_applied, :mapped_value, :casted_to)

    # A distinct text of the file that the column does not accept, with how many times it appears.
    #   value            the text as the file has it
    #   count            how many times the text appears
    #   mapping_applied  whether the value mapping has an entry for the text, and it was applied
    #   mapped_value     what is loaded for the text: what the value mapping gives, in its own shape, or the text
    #                    itself when the mapping has no entry for it
    #   casted_to        the mapped value read as the column's type, in plain JSON types; nil when the type cannot
    #                    read it
    #   reason           why the column does not accept it: +:value_not_castable+, +:value_too_long+,
    #                    +:value_out_of_range+ or +:value_not_allowed+
    IncompatibleValue = Data.define(:value, :count, :mapping_applied, :mapped_value, :casted_to, :reason)
  end
end
