# frozen_string_literal: true

require "active_job"
require "active_job/test_helper"

RSpec.describe EventBus::Jobs::AsyncHandlerJob, type: :job do
  include ActiveJob::TestHelper
  # Test handler class
  class TestAsyncHandler
    attr_reader :called_with

    def call(event)
      @called_with = event
    end
  end

  # Failing handler for error testing
  class FailingAsyncHandler
    def call(event)
      raise StandardError, "Handler failed"
    end
  end

  before do
    # Setup ActiveJob test adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
  end

  describe "#perform" do
    it "executes handler with event data" do
      handler = TestAsyncHandler.new
      allow(TestAsyncHandler).to receive(:new).and_return(handler)

      described_class.perform_now("TestAsyncHandler", { order_id: 123, amount: 99.99 })

      expect(handler.called_with).to be_a(OpenStruct)
      expect(handler.called_with.order_id).to eq(123)
      expect(handler.called_with.amount).to eq(99.99)
    end

    it "rebuilds event as OpenStruct from hash" do
      handler = TestAsyncHandler.new
      allow(TestAsyncHandler).to receive(:new).and_return(handler)

      event_data = { order_id: 456, status: "paid" }
      described_class.perform_now("TestAsyncHandler", event_data)

      event = handler.called_with
      expect(event).to respond_to(:order_id)
      expect(event).to respond_to(:status)
      expect(event.order_id).to eq(456)
      expect(event.status).to eq("paid")
    end

    it "raises ConfigurationError when handler class not found" do
      expect {
        described_class.perform_now("NonExistentHandler", { data: "test" })
      }.to raise_error(EventBus::ConfigurationError, /Handler class 'NonExistentHandler' not found/)
    end

    it "re-raises errors for ActiveJob retry mechanism" do
      allow(FailingAsyncHandler).to receive(:new).and_return(FailingAsyncHandler.new)

      expect {
        described_class.perform_now("FailingAsyncHandler", { order_id: 123 })
      }.to raise_error(StandardError, "Handler failed")
    end
  end

  describe "job configuration" do
    it "uses default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "can be enqueued" do
      expect {
        described_class.perform_later("TestAsyncHandler", { order_id: 123 })
      }.not_to raise_error
    end
  end

  describe "handler instantiation" do
    it "creates new handler instance for each execution" do
      handler1 = TestAsyncHandler.new
      handler2 = TestAsyncHandler.new

      allow(TestAsyncHandler).to receive(:new).and_return(handler1, handler2)

      described_class.perform_now("TestAsyncHandler", { order_id: 1 })
      described_class.perform_now("TestAsyncHandler", { order_id: 2 })

      expect(TestAsyncHandler).to have_received(:new).twice
      expect(handler1.called_with.order_id).to eq(1)
      expect(handler2.called_with.order_id).to eq(2)
    end
  end
end
