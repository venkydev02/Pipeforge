# frozen_string_literal: true

RSpec.describe Pipeforge::HeaderAnalyzer::Matcher do
  subject(:matcher) do
    described_class.new(
      inclusion_threshold: inclusion_threshold,
      pair_scorer: Pipeforge::HeaderAnalyzer::PairScorer.new(reorder_penalty: 10)
    )
  end

  let(:inclusion_threshold) { 55 }

  # The part of a target column the matcher reads.
  let(:target_column_class) { Data.define(:name) }

  def target(name)
    target_column_class.new(name: name)
  end

  def match_summaries(matches)
    matches.map { |match| [match.source_column, match.target_column, match.score] }
  end

  describe "#call" do
    describe "matches" do
      it "matches columns with the same name at 100" do
        result = matcher.call(source_columns: ["First Name", "Last Name"], target_columns: [target("first_name"), target("last_name")])

        expect(match_summaries(result.matches)).to eq(
          [["First Name", "first_name", 100.0], ["Last Name", "last_name", 100.0]]
        )
      end

      it "matches the best of several source columns to a target column" do
        result = matcher.call(source_columns: ["User Name", "F Name", "First Name"], target_columns: [target("first_name")])

        expect(match_summaries(result.matches)).to eq([["First Name", "first_name", 100.0]])
      end

      it "takes the reorder penalty off a match whose words are in a different order" do
        result = matcher.call(source_columns: ["Name First"], target_columns: [target("first_name")])

        expect(match_summaries(result.matches)).to eq([["Name First", "first_name", 90.0]])
      end

      it "lists the matches in the order of the target columns" do
        result = matcher.call(
          source_columns: ["First Name", "Last Name"], target_columns: [target("last_name"), target("first_name")]
        )

        expect(result.matches.map(&:target_column)).to eq(%w[last_name first_name])
      end

      it "gives the same result every time" do
        arguments = {source_columns: ["Name", "Email"], target_columns: [target("first_name"), target("email")]}

        expect(matcher.call(**arguments)).to eq(matcher.call(**arguments))
      end

      it "gives the same matches when the source columns are in another order" do
        targets = [target("first_name"), target("last_name"), target("full_name")]
        in_file_order = matcher.call(source_columns: ["First Name", "Name"], target_columns: targets)
        reversed = matcher.call(source_columns: ["Name", "First Name"], target_columns: targets)

        expect(match_summaries(reversed.matches)).to eq(match_summaries(in_file_order.matches))
      end
    end

    describe "pairs with the same score" do
      it "gives a target the source column whose name comes first" do
        result = matcher.call(source_columns: ["Phone 2", "Phone 1"], target_columns: [target("phone")])

        expect(match_summaries(result.matches)).to eq([["Phone 1", "phone", 66.67]])
      end

      it "leaves the other source column unmatched" do
        result = matcher.call(source_columns: ["Phone 1", "Phone 2"], target_columns: [target("phone")])

        expect(result.unmatched_source_columns).to eq(["Phone 2"])
      end

      it "lists the source column that tied in tied_with" do
        result = matcher.call(source_columns: ["Phone 2", "Phone 1"], target_columns: [target("phone")])

        expect(result.matches.first.tied_with).to eq(["Phone 2"])
      end

      it "lists every source column that tied, in name order" do
        result = matcher.call(source_columns: ["Phone 3", "Phone 1", "Phone 2"], target_columns: [target("phone")])

        expect(result.matches.first.tied_with).to eq(["Phone 2", "Phone 3"])
      end

      it "has an empty tied_with when nothing tied" do
        result = matcher.call(source_columns: ["First Name"], target_columns: [target("first_name")])

        expect(result.matches.first.tied_with).to eq([])
      end

      it "does not list a source column with a lower score" do
        result = matcher.call(source_columns: ["Phone", "Phone 2"], target_columns: [target("phone")])

        expect(result.matches.first.tied_with).to eq([])
      end

      it "does not list a source column that was matched with another score" do
        result = matcher.call(source_columns: ["First", "Name"], target_columns: [target("name"), target("first_name")])

        expect(result.matches.map(&:tied_with)).to eq([[], []])
      end
    end

    describe "one source column for several targets" do
      it "shares a source column between the targets that have the same score for it" do
        result = matcher.call(
          source_columns: ["Name"],
          target_columns: [target("first_name"), target("last_name"), target("full_name")]
        )

        expect(match_summaries(result.matches)).to eq(
          [["Name", "first_name", 66.67], ["Name", "last_name", 66.67], ["Name", "full_name", 66.67]]
        )
      end

      it "gives the best pair its own source column and shares the rest" do
        result = matcher.call(
          source_columns: ["First Name", "Name"],
          target_columns: [target("first_name"), target("last_name"), target("full_name")]
        )

        expect(match_summaries(result.matches)).to eq(
          [["First Name", "first_name", 100.0], ["Name", "last_name", 66.67], ["Name", "full_name", 66.67]]
        )
      end

      it "does not share a source column that was matched with a higher score" do
        result = matcher.call(source_columns: ["Name", "First"], target_columns: [target("name"), target("first_name")])

        expect(match_summaries(result.matches)).to eq([["Name", "name", 100.0], ["First", "first_name", 66.67]])
      end

      it "gives a source column to the target that scores it higher, whatever the table order" do
        result = matcher.call(source_columns: ["Last Name"], target_columns: [target("name"), target("last_name")])

        expect(match_summaries(result.matches)).to eq([["Last Name", "last_name", 100.0]])
        expect(result.unmatched_target_columns).to eq(%w[name])
      end

      it "locks the best pair first so the next target takes the next source column" do
        result = matcher.call(
          source_columns: ["Last Name", "Name"], target_columns: [target("last_name"), target("first_name")]
        )

        expect(match_summaries(result.matches)).to eq(
          [["Last Name", "last_name", 100.0], ["Name", "first_name", 66.67]]
        )
      end

      it "gives Name to the target that is exactly Name" do
        result = matcher.call(source_columns: ["Name"], target_columns: [target("name"), target("first_name")])

        expect(match_summaries(result.matches)).to eq([["Name", "name", 100.0]])
        expect(result.unmatched_target_columns).to eq(%w[first_name])
      end
    end

    describe "the inclusion threshold" do
      it "leaves a pair below the threshold unmatched" do
        result = matcher.call(source_columns: ["Addr"], target_columns: [target("address_line_two")])

        expect(result.matches).to be_empty
        expect(result.unmatched_source_columns).to eq(%w[Addr])
        expect(result.unmatched_target_columns).to eq(%w[address_line_two])
      end

      context "when the score equals the threshold" do
        let(:inclusion_threshold) { 50 }

        it "is a match" do
          result = matcher.call(source_columns: ["User Name"], target_columns: [target("first_name")])

          expect(match_summaries(result.matches)).to eq([["User Name", "first_name", 50.0]])
        end
      end

      context "when the score is just under the threshold" do
        let(:inclusion_threshold) { 51 }

        it "is unmatched" do
          result = matcher.call(source_columns: ["User Name"], target_columns: [target("first_name")])

          expect(result.matches).to be_empty
        end
      end

      context "with a threshold that no score reaches" do
        let(:inclusion_threshold) { 101 }

        it "matches nothing" do
          result = matcher.call(source_columns: ["First Name"], target_columns: [target("first_name")])

          expect(result.matches).to be_empty
        end
      end

      it "never makes a pair with a score of 0 a candidate" do
        result = matcher.call(source_columns: ["City"], target_columns: [target("phone")])

        expect(result.matches).to be_empty
        expect(result.unmatched_source_columns).to eq(%w[City])
        expect(result.unmatched_target_columns).to eq(%w[phone])
      end
    end

    describe "the id word" do
      it "matches Company Id to company_id fully" do
        result = matcher.call(source_columns: ["Company Id"], target_columns: [target("company_id")])

        expect(match_summaries(result.matches)).to eq([["Company Id", "company_id", 100.0]])
      end

      it "matches Company to company_id less well, because id is a word of the name" do
        result = matcher.call(source_columns: ["Company"], target_columns: [target("company_id")])

        expect(match_summaries(result.matches)).to eq([["Company", "company_id", 66.67]])
      end

      it "does not match Company Code to company_id at the default threshold" do
        result = matcher.call(source_columns: ["Company Code"], target_columns: [target("company_id")])

        expect(result.matches).to be_empty
      end

      it "gives company_id to Company Id when the file also has Company" do
        result = matcher.call(source_columns: ["Company", "Company Id"], target_columns: [target("company_id")])

        expect(match_summaries(result.matches)).to eq([["Company Id", "company_id", 100.0]])
        expect(result.unmatched_source_columns).to eq(%w[Company])
      end

      it "matches External Id to external_id fully" do
        result = matcher.call(source_columns: ["External Id"], target_columns: [target("external_id")])

        expect(match_summaries(result.matches)).to eq([["External Id", "external_id", 100.0]])
      end

      it "keeps a token id that is the whole name" do
        result = matcher.call(source_columns: ["Id"], target_columns: [target("id")])

        expect(match_summaries(result.matches)).to eq([["Id", "id", 100.0]])
      end
    end

    describe "columns that match nothing" do
      it "lists the unmatched source columns in file order" do
        result = matcher.call(source_columns: ["Zip", "Email", "City"], target_columns: [target("email")])

        expect(result.unmatched_source_columns).to eq(%w[Zip City])
      end

      it "lists the unmatched target columns in table order" do
        result = matcher.call(source_columns: ["Email"], target_columns: [target("phone"), target("email"), target("city")])

        expect(result.unmatched_target_columns).to eq(%w[phone city])
      end

      it "has no matches without source columns" do
        result = matcher.call(source_columns: [], target_columns: [target("email")])

        expect(result.matches).to be_empty
        expect(result.unmatched_target_columns).to eq(%w[email])
      end

      it "has no matches without target columns" do
        result = matcher.call(source_columns: ["Email"], target_columns: [])

        expect(result.matches).to be_empty
        expect(result.unmatched_source_columns).to eq(%w[Email])
      end
    end
  end
end
