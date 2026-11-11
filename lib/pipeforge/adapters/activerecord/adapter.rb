# frozen_string_literal: true

require_relative "model_adapter"

module Pipeforge
  # The target adapter for ActiveRecord. It reads the structure of a model's table and of the
  # application model itself, and nothing else: no row of the table is read.
  #
  # The target is named by its model class (+"User"+). The adapter finds the class among the models
  # that are loaded; it never loads any itself. The table is the model's own table. A name that no
  # loaded model has cannot be used.
  #
  # Only the columns that can be given a source column are in the schema. The primary key (filled
  # by the database), the columns the model ignores, the generated columns and the array columns
  # are left out, so the rest of the engine never hears of them.
  #
  # @example
  #   schema = Pipeforge::ActiveRecordAdapter.new.schema(target_model: "User")
  #   schema.columns.map(&:name)  # => ["email", "company_id"]
  class ActiveRecordAdapter
    # The column types whose size is a number of characters; for the others it is a number of bytes.
    TEXT_TYPES = %w[string text].freeze

    # The attribute type ActiveRecord gives an integer column of SQLite, compared by name because the
    # SQLite adapter of ActiveRecord is loaded only when SQLite is used.
    SQLITE_INTEGER_TYPE = "ActiveRecord::ConnectionAdapters::SQLite3Adapter::SQLite3Integer"

    # The size SQLite gives an integer column whose declared type has no size, such as +bigint+.
    SQLITE_INTEGER_BYTES = 8

    # @param target_model [String] the name of the model to read
    # @return [TargetSchema]
    # @raise [TargetSchemaError] no loaded model has that name (+active_record_model_not_found+), or
    #   the table of the model does not exist (+target_table_not_found+)
    def schema(target_model:)
      model = find_model(target_model: target_model)
      reject_missing_table(model: model)

      TargetSchema.new(table_name: model.table_name, model: model.name, columns: build_columns(model: model))
    end

    # The object that builds the records of the model and preloads their parents.
    #
    # @param target_model [String] the name of the model to load through
    # @return [ActiveRecordModelAdapter]
    # @raise [TargetSchemaError] no loaded model has that name (+active_record_model_not_found+), or
    #   the table of the model does not exist (+target_table_not_found+)
    def model_adapter(target_model:)
      model = find_model(target_model: target_model)
      reject_missing_table(model: model)

      ActiveRecordModelAdapter.new(model: model)
    end

    private

    # The loaded model with that name. An abstract class is not a model of a table, so it is not found.
    def find_model(target_model:)
      model = ActiveRecord::Base.descendants.find do |candidate|
        candidate.name == target_model && !candidate.abstract_class?
      end
      return model unless model.nil?

      raise TargetSchemaError.single(
        code: :active_record_model_not_found,
        message: "no loaded model is named #{target_model}; the model must be loaded before the schema is read",
        model: target_model
      )
    end

    def reject_missing_table(model:)
      # The connection of the model, because a model can use another database than ActiveRecord::Base.
      table_exists = model.with_connection do |connection|
        connection.data_source_exists?(model.table_name)
      end
      return if table_exists

      raise TargetSchemaError.single(
        code: :target_table_not_found,
        message: "table #{model.table_name} of #{model.name} does not exist in the database",
        table: model.table_name
      )
    end

    def build_columns(model:)
      foreign_keys = foreign_keys_of(model: model)
      primary_keys = Array(model.primary_key)
      target_columns = []

      model.columns_hash.each_value do |model_column|
        next unless writable?(model_column: model_column, primary_keys: primary_keys)

        target_columns << build_column(
          model: model,
          model_column: model_column,
          foreign_key: foreign_keys[model_column.name]
        )
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
    def required?(model:, model_column:)
      return false if model_column.null
      return false if model_column.has_default?
      return false if timestamp_filled_by_model?(model: model, column_name: model_column.name)

      model.column_defaults[model_column.name].nil?
    end

    # Whether the model sets the column when it saves a record: a timestamp of a model that
    # records timestamps (+created_at+, +updated_at+ and the like).
    def timestamp_filled_by_model?(model:, column_name:)
      return false unless model.record_timestamps

      model.all_timestamp_attributes_in_model.include?(column_name)
    end

    # Builds the target column from the model's view of the column: its attribute type and
    # +column_defaults+. For an enum column the labels are in +enum_values+, and an integer column
    # is unsigned when its attribute type is ActiveRecord's unsigned integer.
    def build_column(model:, model_column:, foreign_key:)
      attribute_type = model.type_for_attribute(model_column.name)
      type = attribute_type.type.to_s
      text_type = TEXT_TYPES.include?(type)

      TargetColumn.new(
        name: model_column.name,
        type: type,
        sql_type: model_column.sql_type,
        limit: text_type ? nil : size_in_bytes(attribute_type: attribute_type),
        unsigned: attribute_type.is_a?(ActiveRecord::Type::UnsignedInteger),
        max_length: text_type ? attribute_type.limit : nil,
        precision: attribute_type.precision,
        scale: attribute_type.scale,
        default: model.column_defaults[model_column.name],
        enum_values: model.defined_enums[model_column.name],
        required: required?(model: model, model_column: model_column),
        foreign_key: foreign_key
      )
    end

    # The limit of the attribute type: the size in bytes of an integer, the significand bits of a float.
    # A SQLite integer declared with no size holds 8 bytes, which is what its attribute type assumes.
    def size_in_bytes(attribute_type:)
      limit = attribute_type.limit
      return limit unless limit.nil?
      return limit unless attribute_type.class.ancestors.any? { |ancestor| ancestor.name == SQLITE_INTEGER_TYPE }

      SQLITE_INTEGER_BYTES
    end

    # The foreign key columns of the model, by column name, from its +belongs_to+ associations.
    # A polymorphic association and a composite key are not described as foreign keys.
    def foreign_keys_of(model:)
      foreign_keys = {}

      model.reflect_on_all_associations(:belongs_to).each do |reflection|
        next if reflection.polymorphic?
        next unless reflection.foreign_key.is_a?(String)

        foreign_keys[reflection.foreign_key] = ForeignKey.new(
          association: reflection.name.to_s,
          parent_table: reflection.klass.table_name
        )
      end

      foreign_keys
    end
  end
end
