# frozen_string_literal: true

RSpec.describe Pipeforge::Source::ReusableIO do
  subject(:source_io) { described_class.new(io: io) }

  let(:io) { StringIO.new("A,B\n1,2\n") }

  describe ".new" do
    it "accepts an IO that can be read, rewound and seeked" do
      expect { source_io }.not_to raise_error
    end

    context "when the IO has none of the methods the engine needs" do
      let(:io) { Object.new }

      it "raises ArgumentError, naming every missing method" do
        expect { source_io }.to raise_error(ArgumentError, /does not respond to read, rewind, seek\z/)
      end
    end

    context "when the IO lacks only seek" do
      let(:io) { instance_double(IO, read: nil, rewind: 0) }

      it "names just that method" do
        expect { source_io }.to raise_error(ArgumentError, /does not respond to seek\z/)
      end
    end
  end

  describe "reading" do
    it "reads a line" do
      expect(source_io.gets("\n")).to eq("A,B\n")
    end

    it "reads bytes" do
      expect(source_io.read(3)).to eq("A,B")
    end

    it "tells when the end is reached" do
      source_io.read

      expect(source_io.eof?).to be(true)
    end

    it "starts again from the top after a rewind" do
      source_io.read
      source_io.rewind

      expect(source_io.gets("\n")).to eq("A,B\n")
    end

    it "reports the encoding of the IO" do
      expect(source_io.external_encoding).to eq(io.external_encoding)
    end
  end

  describe "closing" do
    it "cannot be closed through the wrapper, so smarter_csv leaves the consumer's IO open" do
      expect(source_io).not_to respond_to(:close)
    end
  end
end
