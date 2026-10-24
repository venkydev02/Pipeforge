# frozen_string_literal: true

module Pipeforge
  # The target adapter for ActiveRecord. It reads the structure of a table and of the
  # application model that uses it, and nothing else: no row of the table is read.
  #
  # The target is named by its table. The adapter finds the model that uses the table among the
  # models that are loaded; it never loads any itself. A table with no loaded model cannot be
  # used. When a model has subclasses on the same table (single table inheritance) the base
  # class is used; when several unrelated models share the table, the one with the first class
  # name is used, and its name is in the schema.
  #
  # Only the columns that can be given a source column are in the schema. The primary key (filled
  # by the database), the columns the model ignores and the generated columns are left out, so
  # the rest of the engine never hears of them.
  #
  # @example
  #   schema = Pipeforge::ActiveRecordAdapter.new.schema(target_table: "users")
  #   schema.columns.map(&:name)  # => ["id", "email", "company_id"]
  class ActiveRecordAdapter
    # The column types whose size is a number of characters; for the others it is a number of bytes.
    TEXT_TYPES = %w[string text].freeze

    # @param target_table [String] the table to read
    # @return [TargetSchema]
    # @raise [TargetSchemaError] the table does not exist (+target_table_not_found+), or no
    #   application model uses it (+active_record_model_not_found+)
    def schema(target_table:)
      reject_missing_table(target_table: target_table)
      model = find_model(target_table: target_table)

      TargetSchema.new(table_name: target_table, model: model.name, columns: build_columns(model: model))
    end

    private

    def reject_missing_table(target_table:)
      table_exists = ActiveRecord::Base.with_connection do |connection|
        connection.data_source_exists?(target_table)
      end
      return if table_exists

      raise TargetSchemaError.single(
        code: :target_table_not_found,
        message: "table #{target_table} does not exist in the database",
        table: target_table
      )
    end

    # The application model of the table, among the models that are loaded; the base class when
    # there is single table inheritance.
    def find_model(target_table:)
      candidates = ActiveRecord::Base.descendants.select do |model|
        !model.abstract_class? && model.table_name == target_table
      end
      base_models = candidates.reject { |model| candidates.include?(model.superclass) }

      if base_models.empty?
        raise TargetSchemaError.single(
          code: :active_record_model_not_found,
          message: "no loaded model uses the table #{target_table}; the model must be loaded " \
                   "before the schema is read",
          table: target_table
        )
      end

      base_models.min_by { |model| model.name.to_s }
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

    # Whether the column can be given a source column: it is not the primary key and not a
    # generated column. The columns the model ignores are not in its column list at all.
    def writable?(model_column:, primary_keys:)
      return false if primary_keys.include?(model_column.name)

      !model_column.virtual?
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
    # +column_defaults+. For an enum column the labels are in +enum_values+.
    def build_column(model:, model_column:, foreign_key:)
      attribute_type = model.type_for_attribute(model_column.name)
      type = attribute_type.type.to_s
      text_type = TEXT_TYPES.include?(type)

      TargetColumn.new(
        name: model_column.name,
        type: type,
        sql_type: model_column.sql_type,
        limit: text_type ? nil : attribute_type.limit,
        max_length: text_type ? attribute_type.limit : nil,
        precision: attribute_type.precision,
        scale: attribute_type.scale,
        default: model.column_defaults[model_column.name],
        enum_values: model.defined_enums[model_column.name],
        required: required?(model: model, model_column: model_column),
        foreign_key: foreign_key
      )
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
