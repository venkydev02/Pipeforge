# frozen_string_literal: true

module Pipeforge
  module HeaderAnalyzer
    # Splits a column name into lowercase word pieces, called tokens, so two column names can be
    # compared word by word (D1 in recommendation-name-matching.md).
    #
    # A name is split on spaces and other non-alphanumeric characters, on camelCase and on
    # acronym runs, and where letters meet digits. Each token is lowercased and otherwise kept as
    # written: a plural is not turned into its singular, because no short rule list does that
    # correctly for every word. Both sides of a comparison go through the same steps, so the
    # tokens line up.
    #
    # @example
    #   tokenizer = Pipeforge::HeaderAnalyzer::Tokenizer.new
    #   tokenizer.call(name: "HTTPServer2")    # => ["http", "server", "2"]
    #   tokenizer.call(name: "user_email")     # => ["user", "email"]
    class Tokenizer
      # @param name [String] a column name such as "FirstName", "first_name" or "First Name"
      # @return [Array<String>] the tokens, in the order they appear in the name
      def call(name:)
        tokens_of(name: name)
      end

      private

      def tokens_of(name:)
        separated_text = separate_words(text: name)
        pieces = separated_text.split(/[^\p{Alnum}]+/)
        words = pieces.reject(&:empty?)

        words.map(&:downcase)
      end

      # Puts a space where one word ends and the next begins without a separator.
      def separate_words(text:)
        after_camel_case = text.gsub(/(\p{Ll}|\p{N})(\p{Lu})/, '\1 \2')
        after_acronym = after_camel_case.gsub(/(\p{Lu})(\p{Lu}\p{Ll})/, '\1 \2')
        after_letter_digit = after_acronym.gsub(/(\p{L})(\p{N})/, '\1 \2')

        after_letter_digit.gsub(/(\p{N})(\p{L})/, '\1 \2')
      end
    end
  end
end
