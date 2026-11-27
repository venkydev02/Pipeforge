# frozen_string_literal: true

require "securerandom"

RSpec.describe Pipeforge::AdapterRegistry do
  describe ".names" do
    subject(:names) { described_class.names }

    context "when the gem is loaded" do
      it "gives activerecord only" do
        expect(names).to eq(["activerecord"])
      end
    end
  end

  describe ".resolve" do
    subject(:resolved_class) { described_class.resolve(name: name) }

    let(:adapter_directory) { Dir.mktmpdir }
    # A class name no other example uses: a file that was required once stays loaded for the whole process.
    let(:class_name) { "RegistrySpecAdapter#{SecureRandom.hex(4)}" }

    before { $LOAD_PATH.unshift(adapter_directory) }

    after do
      $LOAD_PATH.delete(adapter_directory)
      FileUtils.remove_entry(adapter_directory)
    end

    context "when name is activerecord" do
      let(:name) { "activerecord" }

      it "gives Pipeforge::ActiveRecordTarget" do
        expect(resolved_class).to be(Pipeforge::ActiveRecordTarget)
      end
    end

    context "when name is an adapter whose file is not loaded yet" do
      let(:name) { "spec_adapter" }

      before do
        File.write(File.join(adapter_directory, "#{class_name.downcase}.rb"), "class #{class_name}; end\n")
        add_spec_adapter(class_name: class_name, path: class_name.downcase)
      end

      it "requires the file and gives its class" do
        expect(resolved_class.name).to eq(class_name)
      end
    end

    context "when a gem the adapter needs is missing" do
      let(:name) { "spec_adapter" }
      # The reason that follows is RubyGems' own, so only the start of the sentence is compared.
      let(:sentence_start) { /\A#{Regexp.escape(argument_message(:adapter_not_loaded, name: "spec_adapter", reason: ""))}/ }

      before do
        File.write(File.join(adapter_directory, "#{class_name.downcase}.rb"), "gem \"pipeforge_spec_missing_gem\"\n")
        add_spec_adapter(class_name: class_name, path: class_name.downcase)
      end

      it "raises LoadError naming the adapter" do
        expect { resolved_class }.to raise_error(LoadError, sentence_start)
      end
    end
  end
end
