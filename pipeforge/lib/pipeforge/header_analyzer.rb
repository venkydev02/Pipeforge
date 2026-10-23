# frozen_string_literal: true

require_relative "header_analyzer/matcher"

module Pipeforge
  # The header stage (stage 1, ADR-14): matches the columns of the source to the columns of
  # the target table by name only, and tells the consumer the best matches and the state
  # (the metadata) of each target column.
  #
  # It is a service: {.call} is given the header names of the source and the schema of the
  # target, and reads nothing itself. It sees no value of the source and no row of the target,
  # and it keeps nothing between calls. The engine reads the header (and checks it) and asks
  # the target adapter for the schema.
  #
  # @example
  #   result = Pipeforge::HeaderAnalyzer.call(
  #     source_headers: ["First Name", "Zip"], source_identifier: "users.csv", target_schema: schema
  #   )
  #   result.matches["first_name"]  # => {source_column: "First Name", score: 100.0, metadata: {...}}
  module HeaderAnalyzer
    # The outcome of the header stage.
    #   source_identifier            the file path of the source, or its class name
    #   target_table, model          the table and the model the adapter read it from (nil when
    #                                the adapter has no model)
    #   matches                      {target column => {source_column:, score:, metadata:}}, in
    #                                table order: the pairs at or above the inclusion threshold.
    #                                A source column can be in several entries when their scores
    #                                are the same; the consumer chooses which target to keep.
    #   unmatched_source_columns     source columns in no match, in file order
    #   unmatched_target_columns     [{name:, metadata:}] for the target columns without a match,
    #                                in table order
    #
    # The metadata of a target column is its entry in the schema: type, sql_type, limit,
    # max_length, precision, scale, nullable, default and foreign_key (nil, or
    # {association:, parent_table:, required:}).
    Result = Data.define(
      :source_identifier, :target_table, :model, :matches, :unmatched_source_columns,
      :unmatched_target_columns
    ) do
      # @return [Hash] the result as plain JSON types, ready to store or send
      def to_h
        {
          source_identifier: source_identifier,
          target_table: target_table,
          model: model,
          matches: matches,
          unmatched_source_columns: unmatched_source_columns,
          unmatched_target_columns: unmatched_target_columns
        }
      end
    end

    class << self
      # @param source_headers [Array<String>] the column names of the source, in file order,
      #   already checked (not blank, not repeated)
      # @param source_identifier [String] the file path of the source, or its class name
      # @param target_schema [TargetSchema] the schema of the target table
      # @return [Result]
      def call(source_headers:, source_identifier:, target_schema:)
        matcher_result = build_matcher.call(
          source_columns: source_headers, target_columns: target_schema.columns
        )

        build_result(
          source_identifier: source_identifier, target_schema: target_schema, matcher_result: matcher_result
        )
      end

      private

      def build_matcher
        settings = Configuration.recommendation

        Matcher.new(
          inclusion_threshold: settings.inclusion_threshold,
          pair_scorer: PairScorer.new(reorder_penalty: settings.reorder_penalty)
        )
      end

      def build_result(source_identifier:, target_schema:, matcher_result:)
        metadata_by_target = {}

        target_schema.columns.each do |target_column|
          metadata_by_target[target_column.name] = metadata_of(target_column: target_column)
        end

        Result.new(
          source_identifier: source_identifier,
          target_table: target_schema.table_name,
          model: target_schema.model,
          matches: build_matches(matcher_result: matcher_result, metadata_by_target: metadata_by_target),
          unmatched_source_columns: matcher_result.unmatched_source_columns,
          unmatched_target_columns: build_unmatched_targets(
            matcher_result: matcher_result, metadata_by_target: metadata_by_target
          )
        )
      end

      def build_matches(matcher_result:, metadata_by_target:)
        matches = {}

        matcher_result.matches.each do |match|
          matches[match.target_column] = {
            source_column: match.source_column,
            score: match.score,
            metadata: metadata_by_target.fetch(match.target_column)
          }
        end

        matches
      end

      def build_unmatched_targets(matcher_result:, metadata_by_target:)
        unmatched_targets = []

        matcher_result.unmatched_target_columns.each do |target_column_name|
          unmatched_targets << {name: target_column_name, metadata: metadata_by_target.fetch(target_column_name)}
        end

        unmatched_targets
      end

      # The state of a target column as it is in the schema, as plain data: every field of the
      # schema column except its name (the result already carries it), with the foreign key as a
      # hash too, so the result converts to JSON.
      def metadata_of(target_column:)
        metadata = target_column.to_h.except(:name)
        metadata[:foreign_key] = target_column.foreign_key&.to_h

        metadata
      end
    end
  end
end
