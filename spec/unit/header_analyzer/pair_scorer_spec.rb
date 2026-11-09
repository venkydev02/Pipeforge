# frozen_string_literal: true

# The scorer gets the tokens of the left side and of the right side and gives a percentage. Each
# context gives the tokens; the example states the score expected from them. The private methods
# (word points, pairing, the order check, the percentage) are covered through #call, one group for
# each.
RSpec.describe Pipeforge::HeaderAnalyzer::PairScorer do
  subject(:scorer) { described_class.new(reorder_penalty: reorder_penalty) }

  let(:reorder_penalty) { 10 }
  let(:left_tokens) { raise "the context gives left_tokens" }
  let(:right_tokens) { raise "the context gives right_tokens" }
  let(:score) { scorer.call(left_tokens: left_tokens, right_tokens: right_tokens) }

  describe "#call" do
    describe "the contract" do
      context "when neither side has tokens" do
        let(:left_tokens) { [] }
        let(:right_tokens) { [] }

        it "scores 0" do
          expect(score).to eq(0.0)
        end
      end

      context "when only the left side has tokens" do
        let(:left_tokens) { %w[name] }
        let(:right_tokens) { [] }

        it "scores 0" do
          expect(score).to eq(0.0)
        end
      end

      context "when only the right side has tokens" do
        let(:left_tokens) { [] }
        let(:right_tokens) { %w[name] }

        it "scores 0" do
          expect(score).to eq(0.0)
        end
      end
    end

    describe "word points" do
      context "when the tokens are identical" do
        let(:left_tokens) { %w[first] }
        let(:right_tokens) { %w[first] }

        it "scores 100" do
          expect(score).to eq(100.0)
        end
      end

      context "when the shorter token is a prefix of the longer one" do
        let(:left_tokens) { %w[first] }
        let(:right_tokens) { %w[f] }

        it "scores the share of the longer token that the shorter one covers" do
          expect(score).to eq(20.0)
        end
      end

      context "when one token is inside the other but is not its prefix" do
        let(:left_tokens) { %w[name] }
        let(:right_tokens) { %w[username] }

        it "scores 0" do
          expect(score).to eq(0.0)
        end
      end
    end

    describe "the percentage" do
      context "when some tokens have no match" do
        let(:left_tokens) { %w[first name] }
        let(:right_tokens) { %w[first] }

        it "counts them in the score" do
          expect(score).to eq(66.67)
        end
      end
    end

    describe "the pairing" do
      context "when a token on the left side matches several tokens on the right side" do
        let(:left_tokens) { %w[name] }
        let(:right_tokens) { %w[namesake name] }

        it "pairs it with only its best match" do
          expect(score).to eq(66.67)
        end
      end

      context "when a token on the right side matches several tokens on the left side" do
        let(:left_tokens) { %w[namesake name] }
        let(:right_tokens) { %w[name] }

        it "pairs it with only its best match" do
          expect(score).to eq(66.67)
        end
      end

      context "when a token lost its best match to a better pair" do
        let(:left_tokens) { %w[name namesa] }
        let(:right_tokens) { %w[name namesake] }

        it "pairs it with its next best match" do
          expect(score).to eq(87.5)
        end
      end
    end

    describe "the reorder penalty" do
      context "when the matched tokens appear in a different order" do
        let(:left_tokens) { %w[name first] }
        let(:right_tokens) { %w[first name] }

        it "takes the penalty off the score" do
          expect(score).to eq(90.0)
        end

        context "and the best match is not the first token" do
          let(:left_tokens) { %w[f name] }
          let(:right_tokens) { %w[name first] }

          it "takes the penalty off the score" do
            expect(score).to eq(50.0)
          end
        end
      end

      context "when the matched tokens appear in the same order with tokens without a match on both sides" do
        let(:left_tokens) { %w[name of first] }
        let(:right_tokens) { %w[by name first] }

        it "takes no penalty off" do
          expect(score).to eq(66.67)
        end
      end

      context "when the penalty is larger than the score" do
        let(:reorder_penalty) { 100 }
        let(:left_tokens) { %w[name of first] }
        let(:right_tokens) { %w[first name] }

        it "scores 0" do
          expect(score).to eq(0.0)
        end
      end
    end
  end
end
