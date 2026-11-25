# frozen_string_literal: true

RSpec.describe Pipeforge::Error do
  describe ".new" do
    subject(:error) { described_class.new(errors: entries_of_the_error) }

    context "when given a list of entries" do
      let(:entries_of_the_error) { [{code: :first_mistake, message: "first"}] }

      it "is a StandardError that answers errors with that list" do
        expect(error).to be_a(StandardError)
        expect(error.errors).to equal(entries_of_the_error)
      end
    end

    describe "message" do
      context "when given two entries and no message" do
        let(:entries_of_the_error) do
          [{code: :first_mistake, message: "first"}, {code: :second_mistake, message: "second"}]
        end

        it "is the messages of the entries joined with '; '" do
          expect(error.message).to eq("first; second")
        end
      end

      context "when given one entry and no message" do
        let(:entries_of_the_error) { [{code: :first_mistake, message: "first"}] }

        it "is the message of the entry" do
          expect(error.message).to eq("first")
        end
      end

      context "when given two entries and a message" do
        subject(:error) do
          described_class.new(errors: entries_of_the_error, message: "the message given")
        end

        let(:entries_of_the_error) do
          [{code: :first_mistake, message: "first"}, {code: :second_mistake, message: "second"}]
        end

        it "is the message given" do
          expect(error.message).to eq("the message given")
        end
      end
    end
  end

  describe ".single" do
    subject(:error) { error_class.single(code: :first_mistake, message: "first", **fields) }

    let(:error_class) { described_class }

    context "when given a code, a message and fields" do
      let(:fields) { {target_column_name: "email"} }

      it "gives an error with one entry" do
        expect(error.errors.size).to eq(1)
      end
    end

    context "when given the fields target_column_name and source_column_name" do
      let(:fields) { {target_column_name: "email", source_column_name: "Mail"} }
      let(:expected_entries) do
        [{code: :first_mistake, message: "first", target_column_name: "email", source_column_name: "Mail"}]
      end

      it "gives an entry of code, message and the fields" do
        expect(error.errors).to eq(expected_entries)
      end

      # a Hash is equal whatever its order, so the order is read from to_a
      it "keeps code and message before the fields" do
        expect(error.errors.map(&:to_a)).to eq(expected_entries.map(&:to_a))
      end
    end

    context "when given no fields" do
      let(:fields) { {} }
      let(:expected_entries) { [{code: :first_mistake, message: "first"}] }

      it "gives an entry of only code and message" do
        expect(error.errors).to eq(expected_entries)
      end
    end

    context "when called on a subclass" do
      let(:error_class) { Pipeforge::InvalidMappedColumnsError }
      let(:fields) { {} }

      it "gives an error of that subclass" do
        expect(error).to be_an_instance_of(Pipeforge::InvalidMappedColumnsError)
      end
    end
  end

  describe "#codes" do
    subject(:codes) { described_class.new(errors: entries_of_the_error).codes }

    context "when the error has one entry" do
      let(:entries_of_the_error) { [{code: :first_mistake, message: "first"}] }

      it "gives an Array of Symbols" do
        expect(codes).to all(be_a(Symbol))
      end
    end

    context "when three entries have the codes first_mistake, second_mistake and first_mistake" do
      let(:entries_of_the_error) do
        [
          {code: :first_mistake, message: "one"},
          {code: :second_mistake, message: "two"},
          {code: :first_mistake, message: "three"}
        ]
      end
      let(:expected_codes) { %i[first_mistake second_mistake first_mistake] }

      it "gives the code of each entry, in the order of the entries" do
        expect(codes).to eq(expected_codes)
      end
    end
  end

  describe "the error classes" do
    {
      "InvalidMappedColumnsError" => Pipeforge::InvalidMappedColumnsError,
      "TargetSchemaError" => Pipeforge::TargetSchemaError,
      "Source::Error" => Pipeforge::Source::Error
    }.each do |class_name, error_class|
      context "when the class is #{class_name}" do
        it "is a Pipeforge::Error" do
          expect(error_class.ancestors).to include(described_class)
        end
      end
    end
  end
end

RSpec.describe "Pipeforge::InvalidMappedColumnsError::ENTRIES" do
  let(:entries) { Pipeforge::InvalidMappedColumnsError::ENTRIES }

  describe "the keys" do
    let(:expected_codes) do
      %i[target_column_not_in_schema column_missing_source_column mapped_column_not_in_file required_column_unmapped]
    end

    it "are the four codes, in order" do
      expect(entries.keys).to eq(expected_codes)
    end
  end

  describe ":target_column_not_in_schema" do
    subject(:entry) { entries.fetch(:target_column_not_in_schema).call(target_column_name: "emial") }

    let(:expected_entry) do
      {
        code: :target_column_not_in_schema,
        message: "emial is not a column of the target table that can be loaded",
        target_column_name: "emial"
      }
    end

    context "when given a target_column_name" do
      it "gives the whole entry" do
        expect(entry).to eq(expected_entry)
      end
    end
  end

  describe ":column_missing_source_column" do
    subject(:entry) { entries.fetch(:column_missing_source_column).call(target_column_name: "email") }

    let(:expected_entry) do
      {
        code: :column_missing_source_column,
        message: "email has no source_column_name",
        target_column_name: "email"
      }
    end

    context "when given a target_column_name" do
      it "gives the whole entry" do
        expect(entry).to eq(expected_entry)
      end
    end
  end

  describe ":mapped_column_not_in_file" do
    subject(:entry) do
      entries.fetch(:mapped_column_not_in_file).call(target_column_name: "email", source_column_name: "Mail")
    end

    let(:expected_entry) do
      {
        code: :mapped_column_not_in_file,
        message: "email is mapped to the source column Mail, which is not in the file",
        target_column_name: "email",
        source_column_name: "Mail"
      }
    end

    context "when given a target_column_name and a source_column_name" do
      it "gives the whole entry" do
        expect(entry).to eq(expected_entry)
      end
    end
  end

  describe ":required_column_unmapped" do
    subject(:entry) { entries.fetch(:required_column_unmapped).call(target_column_name: "email") }

    let(:expected_entry) do
      {
        code: :required_column_unmapped,
        message: "email is required but no source column is mapped to it",
        target_column_name: "email"
      }
    end

    context "when given a target_column_name" do
      it "gives the whole entry" do
        expect(entry).to eq(expected_entry)
      end
    end
  end
end
