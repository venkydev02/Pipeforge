# frozen_string_literal: true

require_relative "tokenizer"
require_relative "pair_scorer"

module Pipeforge
  module HeaderAnalyzer
    # Matches source columns to target columns by name only. Values, types and constraints never
    # change the result.
    #
    # Every target column is scored against every source column. A pair with a score below the
    # inclusion threshold is never a candidate. The candidates are sorted by score, best first;
    # pairs with the same score are put in the order of the target column name and then the
    # source column name, so the result is the same on every run and does not depend on where the
    # columns sit in the file or the table.
    #
    # The sorted candidates are walked from the top:
    # - a target column that already has a match is skipped;
    # - a source column that was matched with a different score is skipped (the target with the
    #   better score for it keeps it);
    # - any other pair is a match. A source column matched with the same score by an earlier pair
    #   is shared, and the consumer chooses which target column to keep.
    #
    # A target column can have several source columns with the same score. The one whose name
    # comes first is the match, and the others are listed in its +tied_source_column_names+, so the consumer can
    # see the tie. A source column that was already matched with another score is not listed:
    # it was not free to take the target.
    #
    # Every word of a name counts, a trailing +id+ included: +company_id+ matches +Company Id+
    # fully and +Company+ less well.
    #
    # The target columns are given by name. They are only the columns that can be given a source
    # column: the target leaves out the others (the primary key, ignored and generated
    # columns).
    #
    # @example
    #   matcher = Pipeforge::HeaderAnalyzer::Matcher.new(
    #     inclusion_threshold: 55,
    #     pair_scorer: Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10),
    #     tokenizer: Pipeforge::HeaderAnalyzer::Tokenizer.new
    #   )
    #   matcher.call(source_column_names: ["First Name"], target_column_names: ["first_name"]).matches
    class Matcher
      # A source column matched to a target column.
      #   tied_source_column_names  the other source columns that had the same score for this target column and
      #              were free to take it, in name order; empty when nothing tied
      Match = Data.define(:source_column_name, :target_column_name, :score, :tied_source_column_names)

      # The outcome of one matching.
      #   matches                      the matched pairs, in target column order
      #   unmatched_source_column_names     source columns in no match, in file order
      #   unmatched_target_column_names     target columns without a match, in table order
      Result = Data.define(:matches, :unmatched_source_column_names, :unmatched_target_column_names)

      # A column name with its tokens, for a source column or a target column.
      ColumnTokens = Data.define(:name, :tokens)

      # A source column and a target column whose score reaches the inclusion threshold.
      Candidate = Data.define(:source_column_name, :target_column_name, :score)

      # @param inclusion_threshold [Numeric] the lowest score of a match, a number of at least 1
      # @param pair_scorer [PairScorer] scores one target column against one source column
      # @param tokenizer [Tokenizer] splits a column name into tokens
      def initialize(inclusion_threshold:, pair_scorer:, tokenizer:)
        @inclusion_threshold = inclusion_threshold
        @pair_scorer = pair_scorer
        @tokenizer = tokenizer
      end

      # @param source_column_names [Array<String>] the header names of the source, in file order
      # @param target_column_names [Array<String>] the column names of the target table, in table order
      # @return [Result]
      def call(source_column_names:, target_column_names:)
        tokenized_sources = tokenize_columns(column_names: source_column_names)
        tokenized_targets = tokenize_columns(column_names: target_column_names)
        candidates = build_candidates(tokenized_sources: tokenized_sources, tokenized_targets: tokenized_targets)
        picked = pick_matches(ranked_candidates: rank(candidates: candidates))

        Result.new(
          matches: in_table_order(matches: picked[:matches], target_column_names: target_column_names),
          unmatched_source_column_names: source_column_names - picked[:matched_source_columns],
          unmatched_target_column_names: target_column_names - picked[:matched_target_column_names]
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

      # Every pair of a target column and a source column whose score reaches the inclusion
      # threshold.
      def build_candidates(tokenized_sources:, tokenized_targets:)
        candidates = []

        tokenized_targets.each do |tokenized_target|
          tokenized_sources.each do |tokenized_source|
            score = @pair_scorer.call(left_tokens: tokenized_target.tokens, right_tokens: tokenized_source.tokens)
            next if score < @inclusion_threshold

            candidates << Candidate.new(
              source_column_name: tokenized_source.name, target_column_name: tokenized_target.name, score: score
            )
          end
        end

        candidates
      end

      # Best score first. The names only fix the order of pairs with the same score: a target
      # column name and a source column name are each unique, so no two pairs have the same key.
      def rank(candidates:)
        candidates.sort_by { |candidate| [-candidate.score, candidate.target_column_name, candidate.source_column_name] }
      end

      # Walks the ranked candidates and picks the matches. Each match is built when it is picked,
      # with an empty +tied_source_column_names+ list; a later candidate that ties with it (the same target
      # column, the same score, an available source column) adds its source column to that list.
      #
      # @return [Hash] the +matches+ (in the order they were picked), and the names of the
      #   +matched_source_columns+ and +matched_target_column_names+ that have a match
      def pick_matches(ranked_candidates:)
        match_by_target_column_name = {}
        match_score_by_source_column = {}

        ranked_candidates.each do |candidate|
          source_match_score = match_score_by_source_column[candidate.source_column_name]
          source_available = source_match_score.nil? || source_match_score == candidate.score
          next unless source_available

          existing_match = match_by_target_column_name[candidate.target_column_name]
          if existing_match
            existing_match.tied_source_column_names << candidate.source_column_name if existing_match.score == candidate.score
            next
          end

          match_by_target_column_name[candidate.target_column_name] = to_match(candidate: candidate)
          match_score_by_source_column[candidate.source_column_name] = candidate.score if source_match_score.nil?
        end

        {
          matches: match_by_target_column_name.values,
          matched_source_columns: match_score_by_source_column.keys,
          matched_target_column_names: match_by_target_column_name.keys
        }
      end

      # Each target column has at most one match, so the positions are all different.
      def in_table_order(matches:, target_column_names:)
        matches.sort_by { |match| target_column_names.index(match.target_column_name) }
      end

      def to_match(candidate:)
        Match.new(
          source_column_name: candidate.source_column_name,
          target_column_name: candidate.target_column_name,
          score: candidate.score,
          tied_source_column_names: []
        )
      end
    end
  end
end
