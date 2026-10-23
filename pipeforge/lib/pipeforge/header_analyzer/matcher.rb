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
    # The target columns can be any objects that respond to +name+. They are only the columns
    # that can be given a source column: the target adapter leaves out the others (the primary
    # key, ignored and generated columns).
    #
    # @example
    #   matcher = Pipeforge::HeaderAnalyzer::Matcher.new(
    #     inclusion_threshold: 55,
    #     pair_scorer: Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10)
    #   )
    #   matcher.call(source_columns: ["First Name"], target_columns: target_columns).matches
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
      Entry = Data.define(:name, :tokens)
      Candidate = Data.define(:source, :target, :score)

      # @param inclusion_threshold [Numeric] the lowest score of a match
      # @param pair_scorer [PairScorer] scores one target column against one source column
      # @param tokenizer [Tokenizer] splits a column name into tokens
      def initialize(inclusion_threshold:, pair_scorer:, tokenizer: Tokenizer.new)
        @inclusion_threshold = inclusion_threshold
        @pair_scorer = pair_scorer
        @tokenizer = tokenizer
      end

      # @param source_columns [Array<String>] the header names of the source, in file order
      # @param target_columns [Array<#name>] the target columns, in table order
      # @return [Result]
      def call(source_columns:, target_columns:)
        target_names = target_columns.map(&:name)
        sources = build_entries(names: source_columns)
        targets = build_entries(names: target_names)
        ranked = rank(candidates: build_candidates(sources: sources, targets: targets))
        picks = pick_matches(ranked: ranked)
        picked_in_table_order = in_target_order(picked: picks[:candidates], target_names: target_names)

        Result.new(
          matches: picked_in_table_order.map do |candidate|
            to_match(candidate: candidate, tied_with: picks[:tied_sources].fetch(candidate.target.name))
          end,
          unmatched_source_columns: source_columns - picks[:source_names],
          unmatched_target_columns: target_names - picks[:target_names]
        )
      end

      private

      def build_entries(names:)
        entries = []

        names.each do |name|
          entries << Entry.new(name: name, tokens: @tokenizer.call(name: name))
        end

        entries
      end

      # Every pair of a target column and a source column with a score above 0.
      def build_candidates(sources:, targets:)
        candidates = []

        targets.each do |target|
          sources.each do |source|
            score = score_pair(source: source, target: target)
            next unless score.positive?

            candidates << Candidate.new(source: source, target: target, score: score)
          end
        end

        candidates
      end

      def score_pair(source:, target:)
        @pair_scorer.call(target_tokens: target.tokens, source_tokens: source.tokens)
      end

      # Best score first. The names only fix the order of pairs with the same score: a target
      # column name and a source column name are each unique, so no two pairs have the same key.
      def rank(candidates:)
        candidates.sort_by { |candidate| [-candidate.score, candidate.target.name, candidate.source.name] }
      end

      # Walks the ranked pairs down to the inclusion threshold and picks the matches.
      #
      # @return [Hash] +candidates+ (the picked pairs, in the order they were picked) with the
      #   names of the +source_names+ and +target_names+ that were picked, and +tied_sources+
      #   ({target name => names of the free sources that tied with its match})
      def pick_matches(ranked:)
        picked_target_scores = {}
        tied_sources = {}
        source_scores = {}
        picked = []

        ranked.each do |candidate|
          break if candidate.score < @inclusion_threshold

          target_name = candidate.target.name
          source_name = candidate.source.name
          source_score = source_scores[source_name]
          source_free = source_score.nil? || source_score == candidate.score

          if picked_target_scores.key?(target_name)
            tied_sources[target_name] << source_name if source_free && picked_target_scores[target_name] == candidate.score
            next
          end
          next unless source_free

          picked << candidate
          picked_target_scores[target_name] = candidate.score
          tied_sources[target_name] = []
          source_scores[source_name] = candidate.score if source_score.nil?
        end

        {
          candidates: picked, source_names: source_scores.keys, target_names: picked_target_scores.keys,
          tied_sources: tied_sources
        }
      end

      # Each target column has at most one match, so the positions are all different.
      def in_target_order(picked:, target_names:)
        picked.sort_by { |candidate| target_names.index(candidate.target.name) }
      end

      def to_match(candidate:, tied_with:)
        Match.new(
          source_column: candidate.source.name,
          target_column: candidate.target.name,
          score: candidate.score,
          tied_with: tied_with
        )
      end
    end
  end
end
