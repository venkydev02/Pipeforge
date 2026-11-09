# frozen_string_literal: true

module Pipeforge
  module HeaderAnalyzer
    # Scores how well the tokens of one target column (the left side) match the tokens of one
    # source column (the right side). Only names are used, never values.
    #
    # Word points (0 to 1) compare two tokens: identical tokens score 1, a token that is a full
    # prefix of the other scores shorter length / longer length, anything else scores 0
    # (+first+ and +f+ score 0.2, +name+ and +username+ score 0).
    #
    # The score of the two columns is +2 x sum of word points / (left tokens + right tokens)+,
    # as a percentage. Each token is used at most once. Tokens are paired best word points first.
    #
    # Each pair has the position of its left token (the left index) and the position of its right
    # token (the right index). Going through the pairs by the left index, if the right index ever
    # goes down, the paired tokens are in a different order on the two sides and a fixed penalty
    # is subtracted once. A token without a pair is not part of this check.
    #
    # @example
    #   scorer = Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10)
    #   scorer.call(left_tokens: %w[first name], right_tokens: %w[f name])  # => 60.0
    class PairScorer
      # One pairing of a token of the left side with a token of the right side, by position in
      # each list.
      TokenMatch = Data.define(:left_index, :right_index, :points)

      # @param reorder_penalty [Numeric] points subtracted when the paired tokens are in a
      #   different order (0 to 100)
      def initialize(reorder_penalty:)
        @reorder_penalty = reorder_penalty
      end

      # @param left_tokens [Array<String>] the tokens of the target column
      # @param right_tokens [Array<String>] the tokens of the source column
      # @return [Float] the score, 0 to 100, rounded to two decimals
      def call(left_tokens:, right_tokens:)
        token_matches = pair_tokens(left_tokens: left_tokens, right_tokens: right_tokens)
        token_count = left_tokens.size + right_tokens.size

        percentage(
          token_matches: token_matches,
          token_count: token_count,
          reordered: !in_order?(token_matches: token_matches)
        )
      end

      private

      # 0 to 1: how well two tokens match.
      def word_points(left_token:, right_token:)
        shorter, longer = [left_token, right_token].sort_by(&:length)
        return Rational(0) unless longer.start_with?(shorter)

        Rational(shorter.length, longer.length)
      end

      # Pairs each left token with at most one right token, and the other way round, best word
      # points first. A tie is broken by the position of the left token and then of the right token.
      def pair_tokens(left_tokens:, right_tokens:)
        candidates = candidate_matches(left_tokens: left_tokens, right_tokens: right_tokens)
        best_first = candidates.sort_by { |match| [-match.points, match.left_index, match.right_index] }
        used_left_indexes = []
        used_right_indexes = []
        chosen_matches = []

        best_first.each do |match|
          next if used_left_indexes.include?(match.left_index)
          next if used_right_indexes.include?(match.right_index)

          used_left_indexes << match.left_index
          used_right_indexes << match.right_index
          chosen_matches << match
        end

        chosen_matches
      end

      # Every pair of tokens that match at all.
      def candidate_matches(left_tokens:, right_tokens:)
        candidates = []

        left_tokens.each_with_index do |left_token, left_index|
          right_tokens.each_with_index do |right_token, right_index|
            points = word_points(left_token: left_token, right_token: right_token)
            next if points.zero?

            candidates << TokenMatch.new(left_index: left_index, right_index: right_index, points: points)
          end
        end

        candidates
      end

      # True when the right index of the pairs keeps going up: going through the pairs by the left
      # index, the right index never goes down.
      def in_order?(token_matches:)
        by_left_index = token_matches.sort_by(&:left_index)
        right_indexes = by_left_index.map(&:right_index)

        right_indexes == right_indexes.sort
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
