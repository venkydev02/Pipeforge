# frozen_string_literal: true

RSpec.describe Pipeforge::HeaderAnalyzer::Tokenizer do
  subject(:tokenizer) { described_class.new }

  describe "#call" do
    context "with separators" do
      it "splits on spaces" do
        expect(tokenizer.call(name: "First Name")).to eq(%w[first name])
      end

      it "splits on underscores" do
        expect(tokenizer.call(name: "first_name")).to eq(%w[first name])
      end

      it "splits on dashes" do
        expect(tokenizer.call(name: "first-name")).to eq(%w[first name])
      end

      it "splits on dots" do
        expect(tokenizer.call(name: "first.name")).to eq(%w[first name])
      end

      it "treats several separators in a row as one" do
        expect(tokenizer.call(name: "first__ - name")).to eq(%w[first name])
      end
    end

    context "with words joined without a separator" do
      it "splits camelCase" do
        expect(tokenizer.call(name: "firstName")).to eq(%w[first name])
      end

      it "splits PascalCase" do
        expect(tokenizer.call(name: "FirstName")).to eq(%w[first name])
      end

      it "splits an acronym from the word after it" do
        expect(tokenizer.call(name: "HTTPServer")).to eq(%w[http server])
      end

      it "keeps an acronym that ends the name as one token" do
        expect(tokenizer.call(name: "userID")).to eq(%w[user id])
      end

      it "splits letters from digits" do
        expect(tokenizer.call(name: "address2")).to eq(%w[address 2])
      end

      it "splits digits from the letters after them" do
        expect(tokenizer.call(name: "2fa")).to eq(%w[2 fa])
      end

      it "splits a name made of letters, digits and camelCase" do
        expect(tokenizer.call(name: "line1Address")).to eq(%w[line 1 address])
      end
    end

    context "with letters of any case" do
      it "lowercases every token" do
        expect(tokenizer.call(name: "FIRST NAME")).to eq(%w[first name])
      end
    end

    context "with plural words" do
      it "keeps a plural as written" do
        expect(tokenizer.call(name: "companies")).to eq(%w[companies])
      end

      it "keeps a regular plural as written" do
        expect(tokenizer.call(name: "Names")).to eq(%w[names])
      end
    end

    context "with a name that has no letters or digits" do
      it "gives no tokens" do
        expect(tokenizer.call(name: "--  ..")).to eq([])
      end

      it "gives no tokens for an empty name" do
        expect(tokenizer.call(name: "")).to eq([])
      end
    end
  end
end
