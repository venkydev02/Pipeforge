# frozen_string_literal: true

module Pipeforge
  module ColumnValueAnalyzer
    # A distinct text of the file that the column accepts, with how many times it appears.
    #   value      the text as the file has it
    #   count      how many times the text appears
    #   casted_to  the text read as the column's type, in plain JSON types; nil for the JSON null
    CompatibleValue = Data.define(:value, :count, :casted_to)

    # A distinct text of the file that the column does not accept, with how many times it appears.
    #   value      the text as the file has it
    #   count      how many times the text appears
    #   casted_to  the text read as the column's type, in plain JSON types; nil when the type cannot read it
    #   reason     why the column does not accept it: +:value_not_castable+, +:value_too_long+,
    #              +:value_out_of_range+ or +:value_not_allowed+
    IncompatibleValue = Data.define(:value, :count, :casted_to, :reason)
  end
end
