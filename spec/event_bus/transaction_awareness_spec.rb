# frozen_string_literal: true

require "active_record"
require "sqlite3"

RSpec.describe EventBus, "transaction awareness" do
  # Setup in-memory SQLite database for transaction testing
  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:",
    )

    # Create test table
    ActiveRecord::Schema.define do
      create_table :test_models, force: true do |t|
        t.string :name
      end
    end
  end

  # Test model
  class TestModel < ActiveRecord::Base
  end

  # Test event
  class TransactionTestEvent
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def to_h
      { data: @data }
    end

    def partition_key
      data
    end
  end

  # Test handler that records calls
  class RecordingHandler
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(event)
      @calls << event.data
    end
  end

  let(:handler) { RecordingHandler.new }

  before do
    EventBus.clear!
    EventBus.subscribe(TransactionTestEvent, handler)
    handler.calls.clear
  end

  after do
    EventBus.clear!
  end

  describe "#in_transaction?" do
    it "returns false when outside transaction" do
      expect(EventBus.in_transaction?).to eq(false)
    end

    it "returns true when inside transaction" do
      ActiveRecord::Base.transaction do
        expect(EventBus.in_transaction?).to eq(true)
      end
    end

    it "returns true inside nested transactions" do
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.transaction do
          expect(EventBus.in_transaction?).to eq(true)
        end
      end
    end
  end

  describe "#publish with transaction deferral" do
    context "outside transaction" do
      it "executes handlers immediately" do
        EventBus.publish(TransactionTestEvent.new("immediate"))

        expect(handler.calls).to eq(["immediate"])
      end
    end

    context "inside transaction with defer: :auto (default)" do
      it "defers handler execution until commit" do
        ActiveRecord::Base.transaction do
          EventBus.publish(TransactionTestEvent.new("deferred"))

          # Handler should NOT be called yet
          expect(handler.calls).to be_empty
        end

        # After commit, handler should be called
        expect(handler.calls).to eq(["deferred"])
      end

      it "does NOT execute handler if transaction rolls back" do
        expect {
          ActiveRecord::Base.transaction do
            EventBus.publish(TransactionTestEvent.new("rollback"))
            raise ActiveRecord::Rollback
          end
        }.not_to raise_error

        # Handler should NOT be called after rollback
        expect(handler.calls).to be_empty
      end

      it "executes multiple deferred events in order after commit" do
        ActiveRecord::Base.transaction do
          EventBus.publish(TransactionTestEvent.new("first"))
          EventBus.publish(TransactionTestEvent.new("second"))
          EventBus.publish(TransactionTestEvent.new("third"))

          expect(handler.calls).to be_empty
        end

        expect(handler.calls).to eq(["first", "second", "third"])
      end
    end

    context "inside transaction with defer: false (force immediate)" do
      it "executes handler immediately even inside transaction" do
        ActiveRecord::Base.transaction do
          EventBus.publish(TransactionTestEvent.new("forced"), defer: false)

          # Handler should be called immediately
          expect(handler.calls).to eq(["forced"])
        end
      end
    end

    context "with defer: true (force deferral)" do
      it "attempts to defer even outside transaction" do
        # defer: true forces deferral logic even outside transaction
        # ActiveRecord will simply not trigger callbacks since there's no transaction
        # So handler won't be called
        expect {
          EventBus.publish(TransactionTestEvent.new("no_transaction"), defer: true)
        }.not_to raise_error

        # Handler should not be called since there was no transaction to commit
        expect(handler.calls).to be_empty
      end
    end
  end

  describe "nested transactions" do
    it "defers until outer transaction commits" do
      ActiveRecord::Base.transaction do
        EventBus.publish(TransactionTestEvent.new("outer"))

        ActiveRecord::Base.transaction do
          EventBus.publish(TransactionTestEvent.new("inner"))

          expect(handler.calls).to be_empty
        end

        # Still inside outer transaction
        expect(handler.calls).to be_empty
      end

      # After outer commit, all events published
      expect(handler.calls).to eq(["outer", "inner"])
    end

    it "does not execute if inner transaction raises error" do
      expect {
        ActiveRecord::Base.transaction do
          EventBus.publish(TransactionTestEvent.new("outer"))

          ActiveRecord::Base.transaction do
            EventBus.publish(TransactionTestEvent.new("inner"))
            raise StandardError, "Boom!"
          end
        end
      }.to raise_error(StandardError, "Boom!")

      # No events should be executed after exception
      expect(handler.calls).to be_empty
    end
  end

  describe "integration with ActiveRecord models" do
    it "defers events published during model save" do
      ActiveRecord::Base.transaction do
        model = TestModel.create!(name: "test")
        EventBus.publish(TransactionTestEvent.new("model_#{model.id}"))

        expect(handler.calls).to be_empty
      end

      expect(handler.calls.size).to eq(1)
      expect(handler.calls.first).to match(/model_\d+/)
    end

    it "does not execute events if model save fails" do
      expect {
        ActiveRecord::Base.transaction do
          TestModel.create!(name: "test")
          EventBus.publish(TransactionTestEvent.new("failed"))

          # Force rollback
          raise ActiveRecord::Rollback
        end
      }.not_to raise_error

      expect(handler.calls).to be_empty
    end
  end

  describe "#publish_now (bypasses transaction deferral)" do
    it "always executes immediately, even inside transaction" do
      ActiveRecord::Base.transaction do
        EventBus.publish_now(TransactionTestEvent.new("immediate"))

        expect(handler.calls).to eq(["immediate"])
      end
    end

    it "does not wait for transaction commit" do
      calls_during_transaction = nil

      ActiveRecord::Base.transaction do
        EventBus.publish_now(TransactionTestEvent.new("immediate"))
        calls_during_transaction = handler.calls.dup
      end

      expect(calls_during_transaction).to eq(["immediate"])
      expect(handler.calls).to eq(["immediate"])
    end
  end
end
