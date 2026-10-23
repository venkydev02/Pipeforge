# frozen_string_literal: true

require_relative "tokenizer"
require_relative "pair_scorer"

module Pipeforge
  module HeaderAnalyzer
    # Matches source columns to target columns by name only (ADR-12, D5 in
    # recommendation-name-matching.md). Values, types and constraints never change the result.
    #
    # Every target column is scored against every source column. A pair with a score of 0 is
    # never a candidate. The candidates are sorted by score, best first; pairs with the same
    # score are put in the order of the target column name and then the source column name, so
    # the result is the same on every run and does not depend on where the columns sit in the
    # file or the table.
    #
    # The sorted pairs are walked from the top, down to the inclusion threshold:
    # - a target column that already has a match is skipped;
    # - a source column that was matched with a different score is skipped (the target with the
    #   better score for it keeps it);
    # - any other pair is a match. A source column matched with the same score by an earlier pair
    #   is shared, and the consumer chooses which target column to keep.
    #
    # A target column can have several source columns with the same score. The one whose name
    # comes first is the match, and the others are listed in its +tied_with+, so the consumer can
    # see the tie. A source column that was already matched with another score is not listed:
    # it was not free to take the target.
    #
    # Every word of a name counts, a trailing +id+ included: +company_id+ matches +Company Id+
    # fully and +Company+ less well.
    #
    # The target columns are given by name. They are only the columns that can be given a source
    # column: the target adapter leaves out the others (the primary key, ignored and generated
    # columns).
    #
    # @example
    #   matcher = Pipeforge::HeaderAnalyzer::Matcher.new(
    #     inclusion_threshold: 55,
    #     pair_scorer: Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10)
    #   )
    #   matcher.call(source_columns: ["First Name"], target_columns: ["first_name"]).matches
    class Matcher
      # A source column matched to a target column.
      #   tied_with  the other source columns that had the same score for this target column and
      #              were free to take it, in name order; empty when nothing tied
      Match = Data.define(:source_column, :target_column, :score, :tied_with)

      # The outcome of one matching.
      #   matches                      the matched pairs, in target column order
      #   unmatched_source_columns     source columns in no match, in file order
      #   unmatched_target_columns     target columns without a match, in table order
      Result = Data.define(:matches, :unmatched_source_columns, :unmatched_target_columns)

      # A column name with its tokens, for a source column or a target column.
      ColumnTokens = Data.define(:name, :tokens)

      # A source column and a target column that have a score above 0 together.
      Candidate = Data.define(:source_column, :target_column, :score)

      # @param inclusion_threshold [Numeric] the lowest score of a match
      # @param pair_scorer [PairScorer] scores one target column against one source column
      # @param tokenizer [Tokenizer] splits a column name into tokens
      def initialize(inclusion_threshold:, pair_scorer:, tokenizer: Tokenizer.new)
        @inclusion_threshold = inclusion_threshold
        @pair_scorer = pair_scorer
        @tokenizer = tokenizer
      end

      # @param source_columns [Array<String>] the header names of the source, in file order
      # @param target_columns [Array<String>] the column names of the target table, in table order
      # @return [Result]
      def call(source_columns:, target_columns:)
        tokenized_sources = tokenize_columns(column_names: source_columns)
        tokenized_targets = tokenize_columns(column_names: target_columns)
        candidates = build_candidates(tokenized_sources: tokenized_sources, tokenized_targets: tokenized_targets)
        picked = pick_matches(ranked_candidates: rank(candidates: candidates))

        Result.new(
          matches: in_table_order(matches: picked[:matches], target_columns: target_columns),
          unmatched_source_columns: source_columns - picked[:matched_source_columns],
          unmatched_target_columns: target_columns - picked[:matched_target_columns]
        )
      end

      private

      def tokenize_columns(column_names:)
        tokenized_columns = []

        column_names.each do |column_name|
          tokenized_columns << ColumnTokens.new(name: column_name, tokens: @tokenizer.call(name: column_name))
        end

        tokenized_columns
      end

      # Every pair of a target column and a source column with a score above 0.
      def build_candidates(tokenized_sources:, tokenized_targets:)
        candidates = []

        tokenized_targets.each do |tokenized_target|
          tokenized_sources.each do |tokenized_source|
            score = @pair_scorer.call(target_tokens: tokenized_target.tokens, source_tokens: tokenized_source.tokens)
            next unless score.positive?

            candidates << Candidate.new(
              source_column: tokenized_source.name, target_column: tokenized_target.name, score: score
            )
          end
        end

        candidates
      end

      # Best score first. The names only fix the order of pairs with the same score: a target
      # column name and a source column name are each unique, so no two pairs have the same key.
      def rank(candidates:)
        candidates.sort_by { |candidate| [-candidate.score, candidate.target_column, candidate.source_column] }
      end

      # Walks the ranked candidates down to the inclusion threshold and picks the matches. Each
      # match is built when it is picked, with an empty +tied_with+ list; a later candidate that
      # ties with it (the same target column, the same score, an available source column) adds
      # its source column to that list.
      #
      # @return [Hash] the +matches+ (in the order they were picked), and the names of the
      #   +matched_source_columns+ and +matched_target_columns+ that have a match
      def pick_matches(ranked_candidates:)
        match_by_target_column = {}
        match_score_by_source_column = {}

        ranked_candidates.each do |candidate|
          break if candidate.score < @inclusion_threshold

          source_match_score = match_score_by_source_column[candidate.source_column]
          source_available = source_match_score.nil? || source_match_score == candidate.score
          existing_match = match_by_target_column[candidate.target_column]

          if existing_match
            tied = source_available && existing_match.score == candidate.score
            existing_match.tied_with << candidate.source_column if tied
            next
          end
          next unless source_available

          match_by_target_column[candidate.target_column] = to_match(candidate: candidate)
          match_score_by_source_column[candidate.source_column] = candidate.score if source_match_score.nil?
        end

        {
          matches: match_by_target_column.values,
          matched_source_columns: match_score_by_source_column.keys,
          matched_target_columns: match_by_target_column.keys
        }
      end

      # Each target column has at most one match, so the positions are all different.
      def in_table_order(matches:, target_columns:)
        matches.sort_by { |match| target_columns.index(match.target_column) }
      end

      def to_match(candidate:)
        Match.new(
          source_column: candidate.source_column,
          target_column: candidate.target_column,
          score: candidate.score,
          tied_with: []
        )
      end
    end
  end
end
