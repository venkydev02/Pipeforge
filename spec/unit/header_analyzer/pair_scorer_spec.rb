# frozen_string_literal: true

# The scorer gets the tokens of the left side and of the right side and gives a percentage.
# The private methods (word points, pairing, the order check, the percentage) are covered through
# #call, one context for each.
RSpec.describe Pipeforge::HeaderAnalyzer::PairScorer do
  subject(:scorer) { described_class.new(reorder_penalty: reorder_penalty) }

  let(:reorder_penalty) { 10 }

  # The score of the tokens of the left side against the tokens of the right side; each argument
  # is the tokens separated by spaces.
  def score_of(left, right)
    scorer.call(left_tokens: left.split, right_tokens: right.split)
  end

  describe "#call" do
    context "when a side has no tokens (the contract)" do
      it "scores 0 when neither side has tokens" do
        expect(scorer.call(left_tokens: [], right_tokens: [])).to eq(0.0)
      end

      it "scores 0 when only the left side has tokens" do
        expect(scorer.call(left_tokens: %w[name], right_tokens: [])).to eq(0.0)
      end

      it "scores 0 when only the right side has tokens" do
        expect(scorer.call(left_tokens: [], right_tokens: %w[name])).to eq(0.0)
      end
    end

    context "when two tokens are compared (word points)" do
      it "scores 100 when the tokens are identical" do
        expect(score_of("first", "first")).to eq(100.0)
      end

      it "scores the share of the longer token when the shorter one is its prefix" do
        expect(score_of("first", "f")).to eq(20.0)
      end

      it "scores 0 when the tokens do not match" do
        expect(score_of("first", "name")).to eq(0.0)
      end
    end

    context "when some tokens have no match (the percentage)" do
      it "counts the tokens without a match in the score" do
        expect(score_of("first name", "first")).to eq(66.67)
      end
    end

    context "when a token matches more than one token on the other side (the pairing)" do
      it "pairs a token on the left side with only its best match on the right side" do
        expect(score_of("name", "namesake name")).to eq(66.67)
      end

      it "pairs a token on the right side with only its best match on the left side" do
        expect(score_of("namesake name", "name")).to eq(66.67)
      end

      it "gives a token that lost its match its next best one" do
        expect(score_of("name namesa", "name namesake")).to eq(87.5)
      end
    end

    context "when the matched tokens appear in a different order (the reorder penalty)" do
      it "takes the penalty off the score" do
        expect(score_of("name first", "first name")).to eq(90.0)
      end

      it "takes the penalty off when a token without a match sits between the matched tokens" do
        expect(score_of("name of first", "first name")).to eq(70.0)
      end
    end

    context "when the matched tokens appear in the same order" do
      it "takes no penalty off when a token without a match sits between the matched tokens" do
        expect(score_of("name of first", "name first")).to eq(80.0)
      end
    end
  end
end
