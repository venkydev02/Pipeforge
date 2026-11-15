# frozen_string_literal: true

RSpec.describe Pipeforge::Utilities do
  describe ".largest_float" do
    subject(:answer) { described_class.largest_float(limit: limit) }

    describe "SINGLE_FLOAT_LIMIT" do
      context "when limit is nil" do
        let(:limit) { nil }

        it "answers Float::MAX" do
          expect(answer).to eq(Float::MAX)
        end
      end

      context "when limit is 24" do
        let(:limit) { 24 }

        it "answers SINGLE_FLOAT_MAX" do
          expect(answer).to eq(described_class::SINGLE_FLOAT_MAX)
        end
      end

      context "when limit is 25" do
        let(:limit) { 25 }

        it "answers Float::MAX" do
          expect(answer).to eq(Float::MAX)
        end
      end
    end
  end

  describe ".positive_whole_number?" do
    subject(:answer) { described_class.positive_whole_number?(value: value) }

    describe "an Integer" do
      context "when value is 1" do
        let(:value) { 1 }

        it "is true" do
          expect(answer).to be true
        end
      end

      context "when value is 0" do
        let(:value) { 0 }

        it "is false" do
          expect(answer).to be false
        end
      end
    end

    describe "a value that is not an Integer" do
      context "when value is 2.5" do
        let(:value) { 2.5 }

        it "is false" do
          expect(answer).to be false
        end
      end
    end
  end

  describe ".non_negative_whole_number?" do
    subject(:answer) { described_class.non_negative_whole_number?(value: value) }

    describe "an Integer" do
      context "when value is 0" do
        let(:value) { 0 }

        it "is true" do
          expect(answer).to be true
        end
      end

      context "when value is -1" do
        let(:value) { -1 }

        it "is false" do
          expect(answer).to be false
        end
      end
    end

    describe "a value that is not an Integer" do
      context "when value is 1.5" do
        let(:value) { 1.5 }

        it "is false" do
          expect(answer).to be false
        end
      end
    end
  end

  describe ".blank?" do
    subject(:answer) { described_class.blank?(value: value) }

    describe "nil" do
      context "when value is nil" do
        let(:value) { nil }

        it "is true" do
          expect(answer).to be true
        end
      end
    end

    describe "a String" do
      context 'when value is " "' do
        let(:value) { " " }

        it "is true" do
          expect(answer).to be true
        end
      end

      # Contract only: no break fails it.
      context 'when value is "x"' do
        let(:value) { "x" }

        it "is false" do
          expect(answer).to be false
        end
      end
    end

    # A collection reaches blank? only from a value mapping.
    describe "a collection" do
      context "when value is []" do
        let(:value) { [] }

        it "is true" do
          expect(answer).to be true
        end
      end

      # Contract only: a collection that holds something is not blank, even when it holds nil.
      context "when value is [nil]" do
        let(:value) { [nil] }

        it "is false" do
          expect(answer).to be false
        end
      end
    end

    describe "an object that cannot be empty" do
      # false is not blank, so a value mapped to false is kept.
      context "when value is false" do
        let(:value) { false }

        it "is false" do
          expect(answer).to be false
        end
      end
    end
  end
end
