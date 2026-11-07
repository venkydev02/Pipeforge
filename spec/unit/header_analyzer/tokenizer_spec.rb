# frozen_string_literal: true

# Each context gives a name; the example states the tokens expected from it.
RSpec.describe Pipeforge::HeaderAnalyzer::Tokenizer do
  subject(:tokenizer) { described_class.new }

  let(:name) { raise "the context gives name" }
  let(:tokens) { tokenizer.call(name: name) }

  describe "#call" do
    describe "separators" do
      context "when the name has a space, an underscore, a dash and a dot" do
        let(:name) { "a b_c-d.e" }

        it "splits it at each of them" do
          expect(tokens).to eq(%w[a b c d e])
        end
      end

      context "when the name starts and ends with a separator" do
        let(:name) { " first_name " }

        it "gives no empty token" do
          expect(tokens).to eq(%w[first name])
        end
      end
    end

    describe "words joined without a separator" do
      context "when the words are joined in camelCase" do
        let(:name) { "billingAddressLine" }

        it "splits them at each capital letter" do
          expect(tokens).to eq(%w[billing address line])
        end
      end

      context "when the name has acronyms between words" do
        let(:name) { "HTTPServerXMLParser" }

        it "splits each acronym from the words around it" do
          expect(tokens).to eq(%w[http server xml parser])
        end
      end

      context "when the name has digits between words" do
        let(:name) { "address1line2part3" }

        it "splits the digits from the letters" do
          expect(tokens).to eq(%w[address 1 line 2 part 3])
        end
      end
    end

    describe "letters" do
      context "when the name has capital letters" do
        let(:name) { "FIRST NAME" }

        it "lowercases every token" do
          expect(tokens).to eq(%w[first name])
        end
      end

      context "when the name has accented letters and a capital letter that is not English" do
        let(:name) { "ÉcoleÉlève" }

        it "keeps the accented letters and splits at the capital letter" do
          expect(tokens).to eq(%w[école élève])
        end
      end

      context "when the name has a plural word" do
        let(:name) { "companies" }

        it "keeps the plural as written" do
          expect(tokens).to eq(%w[companies])
        end
      end
    end

    describe "a name without tokens" do
      context "when the name has no letters or digits" do
        let(:name) { "--  .." }

        it "gives no tokens" do
          expect(tokens).to eq([])
        end
      end

      context "when the name is empty" do
        let(:name) { "" }

        it "gives no tokens" do
          expect(tokens).to eq([])
        end
      end
    end
  end
end
