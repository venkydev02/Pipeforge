# frozen_string_literal: true

# The tokenizer and the pair scorer are doubles. The tokenizer gives the tokens of each column name
# from a table (the tokens the real tokenizer gives), and the pair scorer gives the score that a
# context names for a (target column, source column) pair, and 0 for any other pair.
#
# Each context gives the columns (source_columns, target_columns) and the scores (score_pairs); the
# example only states the result expected from them.
#
# The groups follow what Matcher#call does, in order:
#   1. the contract: it asks the tokenizer and the pair scorer;
#   2. the inclusion threshold: it keeps the pairs that reach it;
#   3. choosing the source column of a target column: it walks the pairs from the best;
#   4. a source column that several target columns score: shared at the same score, given to the
#      higher score otherwise;
#   5. the order: equal scores are decided by the column name, and the matches and the unmatched
#      columns are listed in a fixed order.
RSpec.describe Pipeforge::HeaderAnalyzer::Matcher do
  subject(:matcher) do
    described_class.new(
      inclusion_threshold: inclusion_threshold,
      pair_scorer: pair_scorer,
      tokenizer: tokenizer
    )
  end

  let(:inclusion_threshold) { 55 }
  let(:tokenizer) { instance_double(Pipeforge::HeaderAnalyzer::Tokenizer) }
  let(:pair_scorer) { instance_double(Pipeforge::HeaderAnalyzer::PairScorer) }
  let(:source_columns) { raise "the context gives source_columns" }
  let(:target_columns) { raise "the context gives target_columns" }
  let(:result) { matcher.call(source_columns: source_columns, target_columns: target_columns) }

  let(:tokens_of_name) do
    {
      "first_name" => %w[first name], "last_name" => %w[last name], "full_name" => %w[full name],
      "user_name" => %w[user name], "f_name" => %w[f name], "name" => %w[name],
      "phone" => %w[phone], "phone_1" => %w[phone 1], "phone_2" => %w[phone 2], "phone_3" => %w[phone 3],
      "email" => %w[email], "zip" => %w[zip], "city" => %w[city]
    }
  end

  before do
    allow(tokenizer).to receive(:call) { |name:| tokens_of_name.fetch(name) }
    score_pairs({})
  end

  # Sets the scores of the pair scorer: {[target column, source column] => score}. The pair scorer
  # receives tokens, so each pair is looked up by the tokens of its two column names.
  def score_pairs(scores)
    scores_by_tokens = {}
    scores.each do |(target_column, source_column), score|
      scores_by_tokens[[tokens_of_name.fetch(target_column), tokens_of_name.fetch(source_column)]] = score
    end

    allow(pair_scorer).to receive(:call) do |left_tokens:, right_tokens:|
      scores_by_tokens.fetch([left_tokens, right_tokens], 0.0)
    end
  end

  def match_of(source:, target:, score:, tied_with: [])
    described_class::Match.new(source_column: source, target_column: target, score: score, tied_with: tied_with)
  end

  def result_of(matches: [], unmatched_source_columns: [], unmatched_target_columns: [])
    described_class::Result.new(
      matches: matches,
      unmatched_source_columns: unmatched_source_columns,
      unmatched_target_columns: unmatched_target_columns
    )
  end

  describe "#call" do
    describe "the contract" do
      context "when there are no source columns" do
        let(:source_columns) { [] }
        let(:target_columns) { ["email"] }

        it "matches nothing and leaves the target columns unmatched" do
          expect(result).to eq(result_of(unmatched_target_columns: ["email"]))
        end
      end

      context "when there are no target columns" do
        let(:source_columns) { ["email"] }
        let(:target_columns) { [] }

        it "matches nothing and leaves the source columns unmatched" do
          expect(result).to eq(result_of(unmatched_source_columns: ["email"]))
        end
      end

      context "when it is given a source column and a target column" do
        let(:source_columns) { ["zip"] }
        let(:target_columns) { ["email"] }

        before { matcher.call(source_columns: source_columns, target_columns: target_columns) }

        it "asks the tokenizer for the tokens of the source column name" do
          expect(tokenizer).to have_received(:call).with(name: "zip")
        end

        it "asks the tokenizer for the tokens of the target column name" do
          expect(tokenizer).to have_received(:call).with(name: "email")
        end

        it "asks the pair scorer to score the target column tokens (left) against the source column tokens (right)" do
          expect(pair_scorer).to have_received(:call).with(left_tokens: %w[email], right_tokens: %w[zip])
        end
      end
    end

    describe "the inclusion threshold" do
      context "when the inclusion threshold is 50" do
        let(:inclusion_threshold) { 50 }
        let(:source_columns) { ["user_name"] }
        let(:target_columns) { ["first_name"] }

        before { score_pairs(["first_name", "user_name"] => pair_score) }

        shared_examples "a pair that is matched" do
          it "matches the pair" do
            expect(result).to eq(
              result_of(matches: [match_of(source: "user_name", target: "first_name", score: pair_score)])
            )
          end
        end

        context "and the score of a pair is greater than the threshold" do
          let(:pair_score) { 60.0 }

          include_examples "a pair that is matched"
        end

        context "and the score of a pair equals the threshold" do
          let(:pair_score) { 50.0 }

          include_examples "a pair that is matched"
        end

        context "and the score of a pair is just under the threshold" do
          let(:pair_score) { 49.99 }

          it "leaves the pair unmatched" do
            expect(result).to eq(
              result_of(unmatched_source_columns: ["user_name"], unmatched_target_columns: ["first_name"])
            )
          end
        end
      end
    end

    describe "choosing the source column of a target column" do
      context "when several source columns score for a target column" do
        let(:source_columns) { ["user_name", "f_name", "first_name"] }
        let(:target_columns) { ["first_name"] }

        before do
          score_pairs(
            ["first_name", "user_name"] => 50.0, ["first_name", "f_name"] => 60.0, ["first_name", "first_name"] => 100.0
          )
        end

        it "matches the source column with the highest score and leaves the other source columns unmatched" do
          expect(result).to eq(
            result_of(
              matches: [match_of(source: "first_name", target: "first_name", score: 100.0)],
              unmatched_source_columns: ["user_name", "f_name"]
            )
          )
        end
      end

      context "when no other source column has the same score as the match" do
        let(:source_columns) { ["first_name"] }
        let(:target_columns) { ["first_name"] }

        before { score_pairs(["first_name", "first_name"] => 100.0) }

        it "leaves tied_with empty" do
          expect(result).to eq(
            result_of(matches: [match_of(source: "first_name", target: "first_name", score: 100.0)])
          )
        end
      end
    end

    describe "a source column that several target columns score" do
      context "when the target columns give it the same score" do
        let(:source_columns) { ["name"] }
        let(:target_columns) { ["first_name", "last_name", "full_name"] }

        before do
          score_pairs(["first_name", "name"] => 66.67, ["last_name", "name"] => 66.67, ["full_name", "name"] => 66.67)
        end

        it "matches the source column to each of those target columns" do
          expect(result).to eq(
            result_of(
              matches: [
                match_of(source: "name", target: "first_name", score: 66.67),
                match_of(source: "name", target: "last_name", score: 66.67),
                match_of(source: "name", target: "full_name", score: 66.67)
              ]
            )
          )
        end
      end

      context "when the target columns give it different scores" do
        let(:source_columns) { ["last_name"] }
        # The higher score is on the second target column, so the order of the table cannot decide.
        let(:target_columns) { ["name", "last_name"] }

        before { score_pairs(["name", "last_name"] => 66.67, ["last_name", "last_name"] => 100.0) }

        it "gives the source column to the target column with the higher score and leaves the other unmatched" do
          expect(result).to eq(
            result_of(
              matches: [match_of(source: "last_name", target: "last_name", score: 100.0)],
              unmatched_target_columns: ["name"]
            )
          )
        end
      end
    end

    describe "the order" do
      context "when source columns have the same score for a target column (a tie)" do
        let(:target_columns) { ["phone"] }

        before do
          score_pairs(["phone", "phone_1"] => 66.67, ["phone", "phone_2"] => 66.67, ["phone", "phone_3"] => 66.67)
        end

        context "and there are two of them" do
          let(:source_columns) { ["phone_2", "phone_1"] }

          it "matches the source column whose name comes first and lists the other one in tied_with" do
            expect(result).to eq(
              result_of(
                matches: [match_of(source: "phone_1", target: "phone", score: 66.67, tied_with: ["phone_2"])],
                unmatched_source_columns: ["phone_2"]
              )
            )
          end
        end

        context "and there are three of them" do
          let(:source_columns) { ["phone_3", "phone_1", "phone_2"] }

          it "lists the other tied source columns in tied_with, in name order" do
            expect(result).to eq(
              result_of(
                matches: [
                  match_of(source: "phone_1", target: "phone", score: 66.67, tied_with: ["phone_2", "phone_3"])
                ],
                unmatched_source_columns: ["phone_3", "phone_2"]
              )
            )
          end
        end
      end

      context "when the target columns are in a different order from the source columns" do
        let(:source_columns) { ["first_name", "last_name"] }
        let(:target_columns) { ["last_name", "first_name"] }

        before { score_pairs(["first_name", "first_name"] => 100.0, ["last_name", "last_name"] => 100.0) }

        it "lists the matches in the order of the target columns" do
          expect(result).to eq(
            result_of(
              matches: [
                match_of(source: "last_name", target: "last_name", score: 100.0),
                match_of(source: "first_name", target: "first_name", score: 100.0)
              ]
            )
          )
        end
      end

      context "when some source columns match nothing" do
        let(:source_columns) { ["zip", "email", "city"] }
        let(:target_columns) { ["email"] }

        before { score_pairs(["email", "email"] => 100.0) }

        it "lists them as unmatched source columns, in file order" do
          expect(result).to eq(
            result_of(
              matches: [match_of(source: "email", target: "email", score: 100.0)],
              unmatched_source_columns: ["zip", "city"]
            )
          )
        end
      end

      context "when some target columns match nothing" do
        let(:source_columns) { ["email"] }
        let(:target_columns) { ["phone", "email", "city"] }

        before { score_pairs(["email", "email"] => 100.0) }

        it "lists them as unmatched target columns, in table order" do
          expect(result).to eq(
            result_of(
              matches: [match_of(source: "email", target: "email", score: 100.0)],
              unmatched_target_columns: ["phone", "city"]
            )
          )
        end
      end
    end
  end
end
