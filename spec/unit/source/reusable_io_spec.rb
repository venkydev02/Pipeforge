# frozen_string_literal: true

RSpec.describe Pipeforge::Source::ReusableIO do
  subject(:reusable_io) { described_class.new(io: source_io) }

  describe ".new" do
    context "when the source IO responds to read, rewind and seek" do
      let(:source_io) { instance_double(StringIO, read: "", rewind: 0, seek: 0) }

      # contract only
      it "gives a ReusableIO" do
        expect(reusable_io).to be_a(described_class)
      end

      it "gives a wrapper that does not respond to close" do
        expect(reusable_io).not_to respond_to(:close)
      end
    end

    describe "a source IO that lacks methods" do
      subject(:missing_entries) do
        described_class.new(io: source_io)
      rescue Pipeforge::Source::UnsupportedSourceError => error
        error.errors.map { |entry| entry.slice(:code, :method) }
      end

      context "when the source IO lacks only read" do
        let(:source_io) { instance_double(StringIO, rewind: 0, seek: 0) }

        it "raises UnsupportedSourceError with the entry source_io_missing_read" do
          expect(missing_entries).to eq([{code: :source_io_missing_read, method: :read}])
        end
      end

      context "when the source IO lacks only rewind" do
        let(:source_io) { instance_double(StringIO, read: "", seek: 0) }

        it "raises UnsupportedSourceError with the entry source_io_missing_rewind" do
          expect(missing_entries).to eq([{code: :source_io_missing_rewind, method: :rewind}])
        end
      end

      context "when the source IO lacks only seek" do
        let(:source_io) { instance_double(StringIO, read: "", rewind: 0) }

        it "raises UnsupportedSourceError with the entry source_io_missing_seek" do
          expect(missing_entries).to eq([{code: :source_io_missing_seek, method: :seek}])
        end
      end

      context "when the source IO lacks read and seek" do
        let(:source_io) { instance_double(StringIO, rewind: 0) }

        it "raises one UnsupportedSourceError listing read, then seek" do
          expect(missing_entries).to eq([
            {code: :source_io_missing_read, method: :read},
            {code: :source_io_missing_seek, method: :seek}
          ])
        end
      end

      [nil, "data.csv"].each do |value_that_is_not_an_io|
        context "when the source IO is #{value_that_is_not_an_io.inspect}" do
          let(:source_io) { value_that_is_not_an_io }

          it "raises one UnsupportedSourceError listing read, rewind, then seek" do
            expect(missing_entries).to eq([
              {code: :source_io_missing_read, method: :read},
              {code: :source_io_missing_rewind, method: :rewind},
              {code: :source_io_missing_seek, method: :seek}
            ])
          end
        end
      end
    end
  end

  describe "#gets, #read, #rewind, #eof? and #external_encoding" do
    # contract only
    it "has them as public methods, gets and read taking any arguments" do
      source_io = StringIO.new
      wrapper = described_class.new(io: source_io)

      expect(wrapper).to respond_to(:gets, :read, :rewind, :eof?, :external_encoding)
      expect([wrapper.method(:gets).arity, wrapper.method(:read).arity]).to eq([-1, -1])
    end

    context "when the source IO is a double with scripted answers" do
      let(:source_io) do
        instance_double(
          StringIO,
          gets: "A,B\n", read: "A,B", seek: 0, rewind: 0, eof?: true,
          external_encoding: Encoding::UTF_8
        )
      end

      it "gives the line the source IO answers to gets" do
        expect(reusable_io.gets).to eq("A,B\n")
      end

      it "gives the text the source IO answers to read" do
        expect(reusable_io.read).to eq("A,B")
      end

      it "gives the answer of the source IO to eof?" do
        expect(reusable_io.eof?).to be(true)
      end

      it "gives the encoding the source IO answers to external_encoding" do
        expect(reusable_io.external_encoding).to eq(Encoding::UTF_8)
      end
    end

    describe "collaboration with a real StringIO holding the text A,B and 1,2" do
      let(:source_io) { StringIO.new("A,B\n1,2\n") }

      describe "#gets" do
        it "passes the separator on and gives the first line" do
          allow(source_io).to receive(:gets).and_call_original
          first_line = reusable_io.gets("\n")

          expect(source_io).to have_received(:gets).with("\n")
          expect(first_line).to eq("A,B\n")
        end
      end

      describe "#read" do
        it "passes the length on and gives that many characters" do
          allow(source_io).to receive(:read).and_call_original

          characters = reusable_io.read(3)

          expect(source_io).to have_received(:read).with(3)
          expect(characters).to eq("A,B")
        end
      end

      describe "#rewind" do
        it "makes the source IO readable again from the start" do
          allow(source_io).to receive(:rewind).and_call_original
          reusable_io.read
          reusable_io.rewind

          first_line = reusable_io.gets("\n")

          expect(source_io).to have_received(:rewind)
          expect(first_line).to eq("A,B\n")
        end
      end

      describe "#eof?" do
        it "is false before the whole source is read and true after" do
          before_reading = reusable_io.eof?
          reusable_io.read

          expect([before_reading, reusable_io.eof?]).to eq([false, true])
        end
      end

      describe "#external_encoding" do
        it "gives the encoding of the source IO" do
          expect(reusable_io.external_encoding).to eq(source_io.external_encoding)
        end
      end
    end
  end
end
