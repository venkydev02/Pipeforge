# frozen_string_literal: true

RSpec.describe Pipeforge::MappedColumns do
  subject(:mapping) do
    described_class.new(
      mapped_columns: mapped_columns, source_header_names: %w[Mail Age Zip], target_columns: target_columns
    )
  end

  let(:email_column) { build_target_column(name: "email") }
  let(:age_column) { build_target_column(name: "age") }

  def without_messages(entries:)
    entries.map { |entry| entry.except(:message) }
  end

  describe ".new" do
    let(:target_columns) { [email_column] }

    context "when given a Hash of entries, the header names and the target columns" do
      let(:mapped_columns) { {email: {source_column_name: "Mail"}} }

      it "gives a MappedColumns" do
        expect(mapping).to be_a(described_class)
      end
    end

    describe "mapped_columns that is not a Hash" do
      context "when mapped_columns is an Array" do
        let(:mapped_columns) { [[:email, {source_column_name: "Mail"}]] }

        it "raises ArgumentError, alone" do
          expect { mapping }.to raise_error(
            ArgumentError, "mapped_columns must be a Hash of target column name => entry, got Array"
          )
        end
      end
    end

    describe "a target column name or an entry that is wrong" do
      context "when the target column name is 1" do
        let(:mapped_columns) { {1 => {source_column_name: "Mail"}} }

        it "raises ArgumentError naming the key and saying it must be a Symbol or a String" do
          expect { mapping }.to raise_error(ArgumentError, "the key 1 of mapped_columns must be a Symbol or a String")
        end
      end

      context "when the entry of email is nil" do
        let(:mapped_columns) { {email: nil} }

        it "raises ArgumentError naming the target column" do
          expect { mapping }.to raise_error(
            ArgumentError, "email must be given as {source_column_name: ...}, got NilClass"
          )
        end
      end

      context "when the target column name is 1 and its entry is nil" do
        let(:mapped_columns) { {1 => nil} }

        it "raises one ArgumentError with both mistakes, the name first" do
          expect { mapping }.to raise_error(
            ArgumentError,
            "the key 1 of mapped_columns must be a Symbol or a String; " \
            "1 must be given as {source_column_name: ...}, got NilClass"
          )
        end
      end
    end

    describe "a key of an entry that is wrong" do
      context "when the key is the Symbol :value_mappping" do
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mappping: {}}} }

        it "raises ArgumentError naming the key and the keys that are read" do
          expect { mapping }.to raise_error(
            ArgumentError,
            "email has the unknown key :value_mappping; the keys are :source_column_name and :value_mapping"
          )
        end
      end

      context "when the key is the String \"value_mappping\"" do
        let(:mapped_columns) { {"email" => {"source_column_name" => "Mail", "value_mappping" => {}}} }

        it "raises ArgumentError naming the key as it was written" do
          expect { mapping }.to raise_error(
            ArgumentError,
            'email has the unknown key "value_mappping"; the keys are :source_column_name and :value_mapping'
          )
        end
      end

      context "when the key is 2" do
        let(:mapped_columns) { {email: {2 => "Mail"}} }

        it "raises ArgumentError naming the key as it was written" do
          expect { mapping }.to raise_error(
            ArgumentError, "email has the unknown key 2; the keys are :source_column_name and :value_mapping"
          )
        end
      end

      context "when value_mapping is an Array" do
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: ["yes"]}} }

        it "raises ArgumentError naming the target column and the class" do
          expect { mapping }.to raise_error(
            ArgumentError,
            "the value_mapping of email must be a Hash of value in the file => value to load, got Array"
          )
        end
      end

      context "when the entry has an unknown key and a value_mapping that is an Array" do
        let(:mapped_columns) do
          {email: {source_column_name: "Mail", value_mappping: {}, value_mapping: ["yes"]}}
        end

        it "raises one ArgumentError with both mistakes" do
          expect { mapping }.to raise_error(
            ArgumentError,
            "email has the unknown key :value_mappping; the keys are :source_column_name and :value_mapping; " \
            "the value_mapping of email must be a Hash of value in the file => value to load, got Array"
          )
        end
      end
    end

    describe "several mistakes, and a shape mistake next to a data mistake" do
      context "when two entries have a wrong shape" do
        let(:mapped_columns) { {email: nil, age: {source_column_name: "Age", value_mapping: ["yes"]}} }

        it "raises one ArgumentError with the mistakes of both, in the order of the entries, joined with \"; \"" do
          expect { mapping }.to raise_error(
            ArgumentError,
            "email must be given as {source_column_name: ...}, got NilClass; " \
            "the value_mapping of age must be a Hash of value in the file => value to load, got Array"
          )
        end
      end

      context "when the shape is wrong and a source column is not in the file" do
        let(:mapped_columns) { {email: nil, age: {source_column_name: "Nope"}} }

        it "raises only the ArgumentError of the shape" do
          expect { mapping }.to raise_error(
            ArgumentError, "email must be given as {source_column_name: ...}, got NilClass"
          )
        end
      end
    end

    describe "what the caller gave" do
      context "when the mapped columns are written with Strings" do
        let(:mapped_columns) { {"email" => {"source_column_name" => "Mail", "value_mapping" => {1 => "one"}}} }
        let(:mapped_columns_as_given) { {"email" => {"source_column_name" => "Mail", "value_mapping" => {1 => "one"}}} }

        it "does not change the caller's Hash" do
          mapping

          expect(mapped_columns).to eq(mapped_columns_as_given)
        end
      end
    end
  end

  describe "#resolved_mapped_columns!" do
    subject(:resolved_mapped_columns) { mapping.resolved_mapped_columns! }

    describe "a valid mapping" do
      let(:target_columns) { [email_column, age_column] }

      context "when every entry fits the file and the table" do
        let(:mapped_columns) do
          {email: {source_column_name: "Mail", value_mapping: {"N/A" => nil}}, age: {source_column_name: "Age"}}
        end
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {"N/A" => nil}, target_column: email_column
            ),
            "age" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Age", value_mapping: {}, target_column: age_column
            )
          }
        end

        it "gives the Hash of ResolvedMappedColumn by target column name" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end

        it "gives them in the order the consumer gave" do
          expect(resolved_mapped_columns.keys).to eq(%w[email age])
        end

        it "gives each the target column of its name, as the same object" do
          expect(resolved_mapped_columns.fetch("age").target_column).to be(age_column)
        end
      end
    end

    describe "the keys, written in either form" do
      let(:target_columns) { [email_column] }
      let(:expected_resolved_mapped_columns) do
        {
          "email" => Pipeforge::ResolvedMappedColumn.new(
            source_column_name: "Mail", value_mapping: {"ok" => "active"}, target_column: email_column
          )
        }
      end

      context "when the target names and the entry keys are Strings" do
        let(:mapped_columns) { {"email" => {"source_column_name" => "Mail", "value_mapping" => {"ok" => "active"}}} }

        it "gives the same as when they are Symbols" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when the target name is a Symbol and the entry keys are Strings" do
        let(:mapped_columns) { {email: {"source_column_name" => "Mail", "value_mapping" => {"ok" => "active"}}} }

        it "gives the same result" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when two target names give the same text" do
        let(:mapped_columns) { {"email" => {source_column_name: "Age"}, :email => {source_column_name: "Mail"}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            )
          }
        end

        it "uses the later one" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when two keys of an entry give the same Symbol" do
        let(:mapped_columns) { {email: {"source_column_name" => "Age", :source_column_name => "Mail"}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            )
          }
        end

        it "uses the later one" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end
    end

    describe "the value mapping" do
      let(:target_columns) { [email_column] }

      context "when a key of the value mapping is 1" do
        let(:value_mapping_with_a_number_as_key) { {1 => "one", "N/A" => nil} }
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: value_mapping_with_a_number_as_key}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {"1" => "one", "N/A" => nil}, target_column: email_column
            )
          }
        end

        it "turns the key into text and keeps the values" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end

        it "does not change the caller's value mapping" do
          resolved_mapped_columns

          expect(value_mapping_with_a_number_as_key).to eq({1 => "one", "N/A" => nil})
        end
      end

      context "when two keys give the same text (1 and \"1\")" do
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: {1 => "x", "1" => "later"}}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {"1" => "later"}, target_column: email_column
            )
          }
        end

        it "gives one key, and the later one is used" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when value_mapping is nil" do
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: nil}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            )
          }
        end

        it "gives an empty value mapping" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when there is no value_mapping" do
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            )
          }
        end

        it "gives an empty value mapping" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when the values are nil, a blank text, false and a number" do
        let(:value_mapping_with_empty_values) { {"N/A" => nil, "-" => "", "no" => false, "one" => 1} }
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: value_mapping_with_empty_values}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: value_mapping_with_empty_values, target_column: email_column
            )
          }
        end

        it "accepts them and keeps the values as they are" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end
    end

    describe "a mapping that fits" do
      context "when no target column is required and nothing is mapped" do
        let(:target_columns) { [email_column] }
        let(:mapped_columns) { {} }

        it "gives an empty Hash" do
          expect(resolved_mapped_columns).to eq({})
        end
      end

      context "when one source column is mapped to two target columns" do
        let(:target_columns) { [email_column, age_column] }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}, age: {source_column_name: "Mail"}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            ),
            "age" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: age_column
            )
          }
        end

        it "accepts it, because the consumer may do that on purpose" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end

      context "when a column that is not required has no entry" do
        let(:target_columns) { [email_column, age_column] }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}} }
        let(:expected_resolved_mapped_columns) do
          {
            "email" => Pipeforge::ResolvedMappedColumn.new(
              source_column_name: "Mail", value_mapping: {}, target_column: email_column
            )
          }
        end

        it "reports no error" do
          expect(resolved_mapped_columns).to eq(expected_resolved_mapped_columns)
        end
      end
    end

    describe "a data mistake" do
      let(:required_email_column) { build_target_column(name: "email", required: true) }
      let(:required_name_column) { build_target_column(name: "name", required: true) }

      context "when the target column is not in the table" do
        let(:target_columns) { [email_column] }
        let(:mapped_columns) { {email: {source_column_name: "Mail"}, nowhere: {source_column_name: "Zip"}} }

        it "raises InvalidMappedColumnsError with target_column_not_in_schema" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [{code: :target_column_not_in_schema, target_column_name: "nowhere"}]
            )
          end
        end
      end

      context "when an entry has no source column" do
        let(:target_columns) { [email_column] }
        let(:mapped_columns) { {email: {value_mapping: {}}} }

        it "raises InvalidMappedColumnsError with column_missing_source_column" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [{code: :column_missing_source_column, target_column_name: "email"}]
            )
          end
        end
      end

      context "when the source column is not in the file" do
        let(:target_columns) { [email_column] }
        let(:mapped_columns) { {email: {source_column_name: "Nope"}} }

        it "raises InvalidMappedColumnsError with mapped_column_not_in_file" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [{code: :mapped_column_not_in_file, target_column_name: "email", source_column_name: "Nope"}]
            )
          end
        end
      end

      context "when a required target column has no entry" do
        let(:target_columns) { [required_email_column, age_column] }
        let(:mapped_columns) { {age: {source_column_name: "Age"}} }

        it "raises InvalidMappedColumnsError with required_column_unmapped" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [{code: :required_column_unmapped, target_column_name: "email"}]
            )
          end
        end
      end

      context "when two required target columns have no entry" do
        let(:target_columns) { [required_email_column, age_column, required_name_column] }
        let(:mapped_columns) { {age: {source_column_name: "Age"}} }

        it "raises one entry for each, in the order of the table" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [
                {code: :required_column_unmapped, target_column_name: "email"},
                {code: :required_column_unmapped, target_column_name: "name"}
              ]
            )
          end
        end
      end

      context "when a required target column has an entry that names no source column" do
        let(:target_columns) { [required_email_column] }
        let(:mapped_columns) { {email: {}} }

        it "raises only column_missing_source_column" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [{code: :column_missing_source_column, target_column_name: "email"}]
            )
          end
        end
      end

      context "when several mistakes are made at once" do
        let(:target_columns) { [required_email_column, age_column] }
        let(:mapped_columns) { {nowhere: {source_column_name: "Nope"}, age: {}} }

        it "lists every one: each entry first (its target column, then its source column), then the required columns" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(without_messages(entries: error.errors)).to eq(
              [
                {code: :target_column_not_in_schema, target_column_name: "nowhere"},
                {code: :mapped_column_not_in_file, target_column_name: "nowhere", source_column_name: "Nope"},
                {code: :column_missing_source_column, target_column_name: "age"},
                {code: :required_column_unmapped, target_column_name: "email"}
              ]
            )
          end
        end
      end
    end

    describe "collaboration" do
      context "when the mapping has the four data mistakes at once" do
        let(:target_columns) { [build_target_column(name: "email", required: true), age_column] }
        let(:mapped_columns) { {nowhere: {source_column_name: "Nope"}, age: {}} }
        let(:expected_error_entries) do
          entries = Pipeforge::InvalidMappedColumnsError::ENTRIES
          [
            entries.fetch(:target_column_not_in_schema).call(target_column_name: "nowhere"),
            entries.fetch(:mapped_column_not_in_file).call(target_column_name: "nowhere", source_column_name: "Nope"),
            entries.fetch(:column_missing_source_column).call(target_column_name: "age"),
            entries.fetch(:required_column_unmapped).call(target_column_name: "email")
          ]
        end

        it "raises the entries that ENTRIES builds for each code, in order" do
          expect { resolved_mapped_columns }.to raise_error(Pipeforge::InvalidMappedColumnsError) do |error|
            expect(error.errors).to eq(expected_error_entries)
          end
        end
      end

      context "when the mapping is valid" do
        let(:target_columns) { [email_column] }
        let(:mapped_columns) { {email: {source_column_name: "Mail", value_mapping: {1 => "one"}}} }

        it "builds each ResolvedMappedColumn from the entry and the target column of its name" do
          allow(Pipeforge::ResolvedMappedColumn).to receive(:new).and_call_original

          resolved_mapped_columns

          expect(Pipeforge::ResolvedMappedColumn).to have_received(:new).with(
            source_column_name: "Mail", value_mapping: {"1" => "one"}, target_column: email_column
          )
        end
      end
    end
  end
end
