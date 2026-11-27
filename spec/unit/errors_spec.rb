# frozen_string_literal: true

RSpec.shared_examples "a catalog keyed by its codes" do
  it "are the codes, in order" do
    expect(catalog.keys).to eq(expected_codes)
  end
end

RSpec.shared_examples "an entry built from its facts" do
  it "gives the whole entry" do
    expect(entry).to eq(expected_entry)
  end
end

RSpec.shared_examples "a message built from its facts" do
  it "gives the whole sentence" do
    expect(message).to eq(expected_message)
  end
end

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
    let(:catalog) { entries }
    let(:expected_codes) do
      %i[target_column_not_in_schema column_missing_source_column mapped_column_not_in_file required_column_unmapped]
    end

    include_examples "a catalog keyed by its codes"
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
      include_examples "an entry built from its facts"
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
      include_examples "an entry built from its facts"
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
      include_examples "an entry built from its facts"
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
      include_examples "an entry built from its facts"
    end
  end
end

RSpec.describe "Pipeforge::TargetSchemaError::ENTRIES" do
  let(:entries) { Pipeforge::TargetSchemaError::ENTRIES }

  describe "the keys" do
    let(:catalog) { entries }
    let(:expected_codes) { %i[model_not_found target_table_not_found] }

    include_examples "a catalog keyed by its codes"
  end

  describe ":model_not_found" do
    subject(:entry) { entries.fetch(:model_not_found).call(target_model_name: "Customer") }

    let(:expected_entry) do
      {
        code: :model_not_found,
        message: "no loaded model is named Customer; the model must be loaded before the schema is read",
        model_name: "Customer"
      }
    end

    context "when given a target_model_name" do
      include_examples "an entry built from its facts"
    end
  end

  describe ":target_table_not_found" do
    subject(:entry) { entries.fetch(:target_table_not_found).call(table_name: "customers", model_name: "Customer") }

    let(:expected_entry) do
      {
        code: :target_table_not_found,
        message: "table customers of Customer does not exist in the database",
        table_name: "customers"
      }
    end

    context "when given a table_name and a model_name" do
      include_examples "an entry built from its facts"
    end
  end
end

RSpec.describe "Pipeforge::Source::Error::ENTRIES" do
  let(:entries) { Pipeforge::Source::Error::ENTRIES }

  describe "the keys" do
    let(:catalog) { entries }
    let(:expected_codes) do
      %i[source_empty source_header_blank source_header_duplicated malformed_row source_row_too_long]
    end

    include_examples "a catalog keyed by its codes"
  end

  describe ":source_empty" do
    subject(:entry) { entries.fetch(:source_empty).call }

    let(:expected_entry) do
      {code: :source_empty, message: "the source has no header row to read"}
    end

    context "when given no facts" do
      include_examples "an entry built from its facts"
    end
  end

  describe ":source_header_blank" do
    subject(:entry) { entries.fetch(:source_header_blank).call(position: 3) }

    let(:expected_entry) do
      {code: :source_header_blank, message: "header cell 3 is blank", position: 3}
    end

    context "when given a position" do
      include_examples "an entry built from its facts"
    end
  end

  describe ":source_header_duplicated" do
    subject(:entry) do
      entries.fetch(:source_header_duplicated).call(source_column_name: "Mail", count: 3)
    end

    let(:expected_entry) do
      {
        code: :source_header_duplicated,
        message: "column name Mail appears 3 times",
        source_column_name: "Mail"
      }
    end

    context "when given a source_column_name and a count" do
      include_examples "an entry built from its facts"
    end
  end

  describe ":malformed_row" do
    subject(:entry) { entries.fetch(:malformed_row).call(line: 7, reason: "unclosed quoted field") }

    let(:expected_entry) do
      {code: :malformed_row, message: "malformed CSV at line 7: unclosed quoted field", line: 7}
    end

    context "when given a line and a reason" do
      include_examples "an entry built from its facts"
    end
  end

  describe ":source_row_too_long" do
    subject(:entry) { entries.fetch(:source_row_too_long).call(line: 9) }

    let(:expected_entry) do
      {
        code: :source_row_too_long,
        message: "the row at line 9 has more cells than the header",
        line: 9
      }
    end

    context "when given a line" do
      include_examples "an entry built from its facts"
    end
  end
end

RSpec.describe "Pipeforge::ArgumentMessages::MESSAGES" do
  let(:messages) { Pipeforge::ArgumentMessages::MESSAGES }

  describe "the keys" do
    let(:catalog) { messages }
    let(:expected_codes) do
      %i[
        mode_not_allowed
        value_not_whole_number_at_least_0
        value_not_whole_number_at_least_1
        value_not_whole_number_from_0_to_100
        source_missing_methods
        error_not_from_error_catalog
        mapped_columns_not_a_hash
        mapped_column_name_not_symbol_or_string
        mapped_column_entry_not_a_hash
        value_mapping_not_a_hash
        mapped_column_unknown_key
        settings_not_name_value_entries
        settings_engine_not_sections
        settings_not_valid_yaml
        settings_section_unknown
        settings_section_not_settings
        settings_setting_unknown
        settings_file_has_errors
      ]
    end

    include_examples "a catalog keyed by its codes"
  end

  describe ":mode_not_allowed" do
    subject(:message) { messages.fetch(:mode_not_allowed).call(mode: mode) }

    context "when given a mode" do
      let(:mode) { :commit }
      let(:expected_message) { "mode must be :dry_run or :run, got :commit" }

      include_examples "a message built from its facts"
    end
  end

  describe ":value_not_whole_number_at_least_0" do
    subject(:message) do
      messages.fetch(:value_not_whole_number_at_least_0).call(name: name, value: value)
    end

    context "when given a name and a value" do
      let(:name) { "offset" }
      let(:value) { -1 }
      let(:expected_message) { "offset must be a whole number of at least 0, got -1" }

      include_examples "a message built from its facts"
    end
  end

  describe ":value_not_whole_number_at_least_1" do
    subject(:message) do
      messages.fetch(:value_not_whole_number_at_least_1).call(name: name, value: value)
    end

    context "when given a name and a value" do
      let(:name) { "chunk_size" }
      let(:value) { "ten" }
      let(:expected_message) { 'chunk_size must be a whole number of at least 1, got "ten"' }

      include_examples "a message built from its facts"
    end
  end

  describe ":value_not_whole_number_from_0_to_100" do
    subject(:message) do
      messages.fetch(:value_not_whole_number_from_0_to_100).call(name: name, value: value)
    end

    context "when given a name and a value" do
      let(:name) { "threshold" }
      let(:value) { 101 }
      let(:expected_message) { "threshold must be a whole number from 0 to 100, got 101" }

      include_examples "a message built from its facts"
    end
  end

  describe ":source_missing_methods" do
    subject(:message) do
      messages.fetch(:source_missing_methods).call(
        required_method_names: required_method_names,
        missing_method_names: missing_method_names
      )
    end

    context "when given the required_method_names read and rewind and the missing_method_names rewind" do
      let(:required_method_names) { %w[read rewind] }
      let(:missing_method_names) { %w[rewind] }
      let(:expected_message) { "the source must respond to read, rewind; it does not respond to rewind" }

      include_examples "a message built from its facts"
    end

    context "when given two missing_method_names" do
      let(:required_method_names) { %w[read rewind close] }
      let(:missing_method_names) { %w[rewind close] }
      let(:expected_message) do
        "the source must respond to read, rewind, close; it does not respond to rewind, close"
      end

      it "gives the whole sentence with each list joined with ', '" do
        expect(message).to eq(expected_message)
      end
    end
  end

  describe ":error_not_from_error_catalog" do
    subject(:message) do
      messages.fetch(:error_not_from_error_catalog).call(given_class: given_class)
    end

    context "when given a given_class" do
      let(:given_class) { String }
      let(:expected_message) do
        "add_error takes an error built by ErrorCatalog (ErrorCatalog::ERRORS.fetch(key).call(...)), not String"
      end

      include_examples "a message built from its facts"
    end
  end

  describe ":mapped_columns_not_a_hash" do
    subject(:message) do
      messages.fetch(:mapped_columns_not_a_hash).call(given_class: given_class)
    end

    context "when given a given_class" do
      let(:given_class) { Array }
      let(:expected_message) do
        "mapped_columns must be a Hash of target column name => entry, got Array"
      end

      include_examples "a message built from its facts"
    end
  end

  describe ":mapped_column_name_not_symbol_or_string" do
    subject(:message) do
      messages.fetch(:mapped_column_name_not_symbol_or_string).call(target_column_name: target_column_name)
    end

    context "when given a target_column_name" do
      let(:target_column_name) { nil }
      let(:expected_message) { "the key nil of mapped_columns must be a Symbol or a String" }

      include_examples "a message built from its facts"
    end
  end

  describe ":mapped_column_entry_not_a_hash" do
    subject(:message) do
      messages.fetch(:mapped_column_entry_not_a_hash).call(
        target_column_name: target_column_name,
        given_class: given_class
      )
    end

    context "when given a target_column_name and a given_class" do
      let(:target_column_name) { "email" }
      let(:given_class) { String }
      let(:expected_message) { "email must be given as {source_column_name: ...}, got String" }

      include_examples "a message built from its facts"
    end
  end

  describe ":value_mapping_not_a_hash" do
    subject(:message) do
      messages.fetch(:value_mapping_not_a_hash).call(
        target_column_name: target_column_name,
        given_class: given_class
      )
    end

    context "when given a target_column_name and a given_class" do
      let(:target_column_name) { "status" }
      let(:given_class) { Array }
      let(:expected_message) do
        "the value_mapping of status must be a Hash of value in the file => value to load, got Array"
      end

      include_examples "a message built from its facts"
    end
  end

  describe ":mapped_column_unknown_key" do
    subject(:message) do
      messages.fetch(:mapped_column_unknown_key).call(
        target_column_name: target_column_name,
        key: key,
        entry_keys_text: entry_keys_text
      )
    end

    context "when given a target_column_name, a key and an entry_keys_text" do
      let(:target_column_name) { "email" }
      let(:key) { :sourse_column_name }
      let(:entry_keys_text) { "source_column_name, value_mapping" }
      let(:expected_message) do
        "email has the unknown key :sourse_column_name; the keys are source_column_name, value_mapping"
      end

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_not_name_value_entries" do
    subject(:message) { messages.fetch(:settings_not_name_value_entries).call }

    context "when given no facts" do
      let(:expected_message) { "must be made of name: value entries at the top level" }

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_engine_not_sections" do
    subject(:message) { messages.fetch(:settings_engine_not_sections).call }

    context "when given no facts" do
      let(:expected_message) do
        "engine must hold sections, each written as a name with entries under it"
      end

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_not_valid_yaml" do
    subject(:message) { messages.fetch(:settings_not_valid_yaml).call(reason: reason) }

    context "when given a reason" do
      let(:reason) { "did not find expected key at line 3" }
      let(:expected_message) { "not valid YAML: did not find expected key at line 3" }

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_section_unknown" do
    subject(:message) { messages.fetch(:settings_section_unknown).call(section_name: section_name) }

    context "when given a section_name" do
      let(:section_name) { "loadng" }
      let(:expected_message) { "unknown section loadng" }

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_section_not_settings" do
    subject(:message) { messages.fetch(:settings_section_not_settings).call(section_name: section_name) }

    context "when given a section_name" do
      let(:section_name) { "loading" }
      let(:expected_message) { "section loading must hold settings, each written as name: value" }

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_setting_unknown" do
    subject(:message) do
      messages.fetch(:settings_setting_unknown).call(setting_name: setting_name, section_name: section_name)
    end

    context "when given a setting_name and a section_name" do
      let(:setting_name) { "chunk_sise" }
      let(:section_name) { "loading" }
      let(:expected_message) { "unknown setting chunk_sise in section loading" }

      include_examples "a message built from its facts"
    end
  end

  describe ":settings_file_has_errors" do
    subject(:message) do
      messages.fetch(:settings_file_has_errors).call(path: path, error_messages: error_messages)
    end

    context "when given a path and one error message" do
      let(:path) { "config/pipeforge.yml" }
      let(:error_messages) { ["unknown section loadng"] }
      let(:expected_message) { "config/pipeforge.yml: unknown section loadng" }

      it "gives the path, ': ' and the message" do
        expect(message).to eq(expected_message)
      end
    end

    context "when given a path and three error messages" do
      let(:path) { "config/pipeforge.yml" }
      let(:error_messages) do
        ["unknown section loadng", "unknown setting chunk_sise in section loading", "section engine must hold settings"]
      end
      let(:expected_message) do
        "config/pipeforge.yml has 3 errors:\n" \
          "  - unknown section loadng\n" \
          "  - unknown setting chunk_sise in section loading\n" \
          "  - section engine must hold settings"
      end

      it "gives the path with the count, then each message on its own line indented with '  - '" do
        expect(message).to eq(expected_message)
      end
    end
  end
end
