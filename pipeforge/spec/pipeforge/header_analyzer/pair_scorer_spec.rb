# frozen_string_literal: true

RSpec.describe Pipeforge::HeaderAnalyzer::PairScorer do
  subject(:scorer) { described_class.new(reorder_penalty: reorder_penalty) }

  let(:reorder_penalty) { 10 }

  # The score of one target column's tokens against one source column's tokens.
  def score_of(target, source)
    scorer.call(target_tokens: target.split, source_tokens: source.split)
  end

  describe "#call" do
    describe "word points of a single token against a single token" do
      it "scores identical tokens 100" do
        expect(score_of("first", "first")).to eq(100.0)
      end

      it "scores a one letter prefix by its share of the longer token" do
        expect(score_of("first", "f")).to eq(20.0)
      end

      it "scores an abbreviation that is a prefix" do
        expect(score_of("address", "addr")).to eq(57.14)
      end

      it "scores a shorter prefix of a longer token" do
        expect(score_of("number", "num")).to eq(50.0)
      end

      it "penalizes extra letters after the matching part" do
        expect(score_of("name", "namesake")).to eq(50.0)
      end

      it "scores 0 when the token is inside the other but not a prefix" do
        expect(score_of("name", "username")).to eq(0.0)
      end

      it "scores 0 when only the first letters are shared" do
        expect(score_of("phone", "photo")).to eq(0.0)
      end

      it "scores 0 for an abbreviation that is not a prefix" do
        expect(score_of("quantity", "qty")).to eq(0.0)
      end
    end

    describe "columns of several tokens" do
      it "scores 100 for identical columns" do
        expect(score_of("first name", "first name")).to eq(100.0)
      end

      it "scores First Name against F Name" do
        expect(score_of("first name", "f name")).to eq(60.0)
      end

      it "scores First Name against User Name" do
        expect(score_of("first name", "user name")).to eq(50.0)
      end

      it "scores 100 for Name against Name" do
        expect(score_of("name", "name")).to eq(100.0)
      end

      it "scores Name against User Name" do
        expect(score_of("name", "user name")).to eq(66.67)
      end

      it "scores Name against Company Name the same as against User Name" do
        expect(score_of("name", "company name")).to eq(66.67)
      end

      it "uses a source token for at most one target token" do
        expect(score_of("name name", "name")).to eq(66.67)
      end

      it "uses a target token for at most one source token" do
        expect(score_of("name", "name namesake")).to eq(66.67)
      end

      it "scores 0 when no token matches" do
        expect(score_of("phone", "city")).to eq(0.0)
      end

      it "scores 0 when both columns have no tokens" do
        expect(scorer.call(target_tokens: [], source_tokens: [])).to eq(0.0)
      end

      it "scores 0 when one column has no tokens" do
        expect(scorer.call(target_tokens: %w[name], source_tokens: [])).to eq(0.0)
      end
    end

    describe "the reorder penalty" do
      it "takes 10 points off Name First against First Name" do
        expect(score_of("first name", "name first")).to eq(90.0)
      end

      it "takes 10 points off Birth Date against Date of Birth" do
        expect(score_of("birth date", "date of birth")).to eq(70.0)
      end

      it "takes nothing off when the order is the same" do
        expect(score_of("birth date", "birth of date")).to eq(80.0)
      end

      context "with another penalty" do
        let(:reorder_penalty) { 25 }

        it "takes that many points off" do
          expect(score_of("first name", "name first")).to eq(75.0)
        end
      end

      context "with a penalty larger than the score" do
        let(:reorder_penalty) { 100 }

        it "never goes below 0" do
          expect(score_of("first name", "name first")).to eq(0.0)
        end
      end
    end

    describe "pairing order" do
      it "gives a source token to the target token that matches it best" do
        # first matches f at 20 and name matches f at 0; the single f goes to first
        expect(score_of("first name", "f")).to eq(13.33)
      end

      it "gives the same score every time" do
        first_time = score_of("birth date", "date of birth")

        expect(score_of("birth date", "date of birth")).to eq(first_time)
      end
    end
  end
end
