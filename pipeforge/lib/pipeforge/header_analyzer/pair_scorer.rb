# frozen_string_literal: true

module Pipeforge
  module HeaderAnalyzer
    # Scores how well the tokens of one target column match the tokens of one source column.
    # Only names are used, never values.
    #
    # Word points (0 to 1) compare two tokens: identical tokens score 1, a token that is a full
    # prefix of the other scores shorter length / longer length, anything else scores 0
    # (+first+ and +f+ score 0.2, +name+ and +username+ score 0).
    #
    # The score of the two columns is +2 x sum of word points / (target tokens + source tokens)+,
    # as a percentage. Each token is used at most once. Tokens are paired best word points first.
    #
    # If the paired tokens appear in a different left-to-right order on the two sides, a fixed
    # penalty is subtracted once.
    #
    # @example
    #   scorer = Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10)
    #   scorer.call(target_tokens: %w[first name], source_tokens: %w[f name])  # => 60.0
    class PairScorer
      # One pairing of a target token with a source token, by position in each list.
      TokenMatch = Data.define(:target_index, :source_index, :points)

      # @param reorder_penalty [Numeric] points subtracted when the paired tokens are in a
      #   different order (0 to 100)
      def initialize(reorder_penalty:)
        @reorder_penalty = reorder_penalty
      end

      # @param target_tokens [Array<String>] the tokens of the target column
      # @param source_tokens [Array<String>] the tokens of the source column
      # @return [Float] the score, 0 to 100, rounded to two decimals
      def call(target_tokens:, source_tokens:)
        token_matches = pair_tokens(target_tokens: target_tokens, source_tokens: source_tokens)
        token_count = target_tokens.size + source_tokens.size

        percentage(
          token_matches: token_matches,
          token_count: token_count,
          reordered: !in_order?(token_matches: token_matches)
        )
      end

      private

      # 0 to 1: how well two tokens match.
      def word_points(target_token:, source_token:)
        shorter, longer = [target_token, source_token].sort_by(&:length)
        return Rational(0) unless longer.start_with?(shorter)

        Rational(shorter.length, longer.length)
      end

      # Pairs each target token with at most one source token, best word points first. A tie is
      # broken by the position of the target token and then of the source token.
      def pair_tokens(target_tokens:, source_tokens:)
        candidates = candidate_matches(target_tokens: target_tokens, source_tokens: source_tokens)
        best_first = candidates.sort_by { |match| [-match.points, match.target_index, match.source_index] }
        used_target_indexes = []
        used_source_indexes = []
        chosen_matches = []

        best_first.each do |match|
          next if used_target_indexes.include?(match.target_index)
          next if used_source_indexes.include?(match.source_index)

          used_target_indexes << match.target_index
          used_source_indexes << match.source_index
          chosen_matches << match
        end

        chosen_matches
      end

      # Every pair of tokens that match at all.
      def candidate_matches(target_tokens:, source_tokens:)
        candidates = []

        target_tokens.each_with_index do |target_token, target_index|
          source_tokens.each_with_index do |source_token, source_index|
            points = word_points(target_token: target_token, source_token: source_token)
            next if points.zero?

            candidates << TokenMatch.new(target_index: target_index, source_index: source_index, points: points)
          end
        end

        candidates
      end

      # True when, going through the target tokens left to right, the paired source tokens are
      # also left to right.
      def in_order?(token_matches:)
        by_target = token_matches.sort_by(&:target_index)
        source_indexes = by_target.map(&:source_index)

        source_indexes == source_indexes.sort
      end

      # The score as a percentage, less the penalty when the order differs, never below 0.
      def percentage(token_matches:, token_count:, reordered:)
        return 0.0 if token_count.zero?

        sum_of_points = token_matches.sum(&:points)
        score = Rational(2) * sum_of_points / token_count * 100
        score -= @reorder_penalty if reordered

        [score, 0].max.to_f.round(2)
      end
    end
  end
end
