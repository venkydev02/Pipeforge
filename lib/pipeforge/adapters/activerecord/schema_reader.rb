# frozen_string_literal: true

module Pipeforge
  # Reads the structure of one ActiveRecord model's table and of the application model itself, and
  # nothing else: no row of the table is read.
  #
  # Only the columns that can be given a source column are in the schema. The primary key (filled
  # by the database), the columns the model ignores, the generated columns and the array columns
  # are left out, so the rest of the engine never hears of them.
  #
  # @example
  #   schema = Pipeforge::ActiveRecordSchemaReader.new(model: User, enum_labels: {}).call
  #   schema.columns.map(&:name)  # => ["email", "company_id"]
  class ActiveRecordSchemaReader
    # The column types whose size is a number of characters; for the others it is a number of bytes.
    TEXT_TYPES = %w[string text].freeze

    # @param model [Class] the ActiveRecord model of the target table
    # @param enum_labels [Hash{String => Array<String>}] column name => the labels of its enum, for the enum
    #   columns of the model
    def initialize(model:, enum_labels:)
      @model = model
      @enum_labels = enum_labels
    end

    # @return [TargetSchema] the table name, the model name and the columns that can be given a source column
    def call
      TargetSchema.new(table_name: @model.table_name, model_name: @model.name, columns: build_columns)
    end

    private

    def build_columns
      foreign_keys = foreign_keys_by_column_name
      primary_keys = Array(@model.primary_key)
      target_columns = []

      @model.columns_hash.each_value do |model_column|
        next unless writable?(model_column: model_column, primary_keys: primary_keys)

        target_columns << build_column(model_column: model_column, foreign_key: foreign_keys[model_column.name])
      end

      target_columns
    end

    # Whether the column can be given a source column: it is not the primary key, not a generated
    # column and not an array column. The columns the model ignores are not in its column list at all.
    def writable?(model_column:, primary_keys:)
      return false if primary_keys.include?(model_column.name)
      return false if model_column.virtual?

      !array_column?(model_column: model_column)
    end

    # Whether each cell of the column holds a list of values. Only some databases have such columns
    # (PostgreSQL), so the question is asked only of a column that can answer it.
    def array_column?(model_column:)
      model_column.respond_to?(:array?) && model_column.array?
    end

    # Whether a row cannot be loaded without a source column for the column: the column refuses
    # an empty value (+null+ is false) and has no default, neither in the table (a value or a
    # function) nor in the model. The timestamps the model fills itself count as a default.
    def required?(model_column:)
      return false if model_column.null
      return false if model_column.has_default?
      return false if timestamp_filled_by_model?(column_name: model_column.name)

      @model.column_defaults[model_column.name].nil?
    end

    # Whether the model sets the column when it saves a record: a timestamp of a model that
    # records timestamps (+created_at+, +updated_at+ and the like).
    def timestamp_filled_by_model?(column_name:)
      return false unless @model.record_timestamps

      @model.all_timestamp_attributes_in_model.include?(column_name)
    end

    # Builds the target column from the model's view of the column: its attribute type and
    # +column_defaults+. For an enum column the labels are in +enum_labels+, and an integer column
    # is not signed when its attribute type is ActiveRecord's unsigned integer.
    def build_column(model_column:, foreign_key:)
      attribute_type = @model.type_for_attribute(model_column.name)
      type = attribute_type.type.to_s
      text_type = TEXT_TYPES.include?(type)

      TargetColumn.new(
        name: model_column.name,
        type: type,
        sql_type: model_column.sql_type,
        # For a column that is not text: the size in bytes of an integer, the significand bits of a float.
        limit: text_type ? nil : attribute_type.limit,
        is_signed: is_signed_of(attribute_type: attribute_type),
        max_length: text_type ? attribute_type.limit : nil,
        precision: attribute_type.precision,
        scale: attribute_type.scale,
        default: @model.column_defaults[model_column.name],
        enum_labels: @enum_labels[model_column.name],
        required: required?(model_column: model_column),
        foreign_key: foreign_key
      )
    end

    # Whether an integer column holds negative numbers; nil for a column that is not an integer.
    def is_signed_of(attribute_type:)
      return false if attribute_type.is_a?(ActiveRecord::Type::UnsignedInteger)
      return true if attribute_type.type == :integer

      nil
    end

    # The foreign key columns of the model, by column name, from its +belongs_to+ associations.
    # A polymorphic association and a composite key are not described as foreign keys.
    def foreign_keys_by_column_name
      foreign_keys = {}

      @model.reflect_on_all_associations(:belongs_to).each do |reflection|
        next if reflection.polymorphic?
        next unless reflection.foreign_key.is_a?(String)

        foreign_keys[reflection.foreign_key] = ForeignKey.new(
          association_name: reflection.name.to_s,
          parent_table_name: reflection.klass.table_name
        )
      end

      foreign_keys
    end
  end
end
