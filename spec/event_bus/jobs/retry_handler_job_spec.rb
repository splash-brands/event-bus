# frozen_string_literal: true

require "active_job"
require "active_job/test_helper"
require "active_support/notifications"

RSpec.describe EventBus::Jobs::RetryHandlerJob, type: :job do
  include ActiveJob::TestHelper

  # Test handler classes
  class TestRetryHandler
    attr_reader :called_with, :call_count

    def initialize
      @call_count = 0
    end

    def call(event)
      @call_count += 1
      @called_with = event
    end
  end

  class FlakeyRetryHandler
    attr_reader :call_count

    def initialize
      @call_count = 0
    end

    def call(event)
      @call_count += 1
      raise StandardError, "Temporary failure" if @call_count < 2
      # Success on 2nd attempt
    end
  end

  class AlwaysFailingRetryHandler
    def call(event)
      raise StandardError, "Permanent failure"
    end
  end

  before do
    # Setup ActiveJob test adapter
    ActiveJob::Base.queue_adapter = :test
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = false
  end

  describe "#perform" do
    it "executes handler with event data" do
      handler = TestRetryHandler.new
      allow(TestRetryHandler).to receive(:new).and_return(handler)

      described_class.perform_now(
        "TestRetryHandler",
        { order_id: 123 },
        "Original error: Connection timeout",
      )

      expect(handler.called_with).to be_a(OpenStruct)
      expect(handler.called_with.order_id).to eq(123)
      expect(handler.call_count).to eq(1)
    end

    it "rebuilds event as OpenStruct from hash" do
      handler = TestRetryHandler.new
      allow(TestRetryHandler).to receive(:new).and_return(handler)

      event_data = { order_id: 456, status: "failed" }
      described_class.perform_now("TestRetryHandler", event_data, "Error")

      event = handler.called_with
      expect(event).to respond_to(:order_id)
      expect(event).to respond_to(:status)
      expect(event.order_id).to eq(456)
      expect(event.status).to eq("failed")
    end

    it "handles non-existent handler class" do
      # The job will fail and retry, but won't raise in tests due to retry_on
      # In production, this would trigger Sentry after 3 failed attempts
      expect {
        described_class.perform_now("NonExistentHandler", { data: "test" }, "Error")
      }.not_to raise_error
    end

    it "handles failing handlers with retry mechanism" do
      allow(AlwaysFailingRetryHandler).to receive(:new).and_return(AlwaysFailingRetryHandler.new)

      # The job will fail and retry, but won't raise in tests due to retry_on
      # In production, this would trigger Sentry after 3 failed attempts
      expect {
        described_class.perform_now("AlwaysFailingRetryHandler", { order_id: 123 }, "Original error")
      }.not_to raise_error
    end
  end

  describe "#report_retries_exhausted" do
    let(:job_instance) { described_class.new("TestHandler", { order_id: 123 }, "Original error") }
    let(:final_error) { StandardError.new("Final failure after 3 attempts") }

    before do
      # Simulate 3 execution attempts
      allow(job_instance).to receive(:executions).and_return(3)
      allow(job_instance).to receive(:job_id).and_return("job_abc123")
    end

    it "logs exhaustion error without raising" do
      expect {
        job_instance.report_retries_exhausted(final_error)
      }.not_to raise_error
    end

    context "with Sentry available" do
      before do
        # Mock Sentry module
        stub_const("Sentry", Module.new)
        allow(Sentry).to receive(:capture_exception)
      end

      it "reports to Sentry with custom fingerprinting" do
        job_instance.report_retries_exhausted(final_error)

        expect(Sentry).to have_received(:capture_exception).with(
          final_error,
          hash_including(
            tags: hash_including(
              handler: "TestHandler",
              job_class: "EventBus::Jobs::RetryHandlerJob",
            ),
            extra: hash_including(
              event_payload: { order_id: 123 },
              original_error: "Original error",
              final_error: "Final failure after 3 attempts",
              attempts: 3,
              job_id: "job_abc123",
            ),
            fingerprint: [
              "retry_handler_job",
              "TestHandler",
              "StandardError",
            ],
          ),
        )
      end
    end

    context "without Sentry" do
      it "only logs error without Sentry reporting" do
        # Ensure Sentry is not defined
        hide_const("Sentry")

        expect {
          job_instance.report_retries_exhausted(final_error)
        }.not_to raise_error
      end
    end
  end

  describe "ActiveSupport::Notifications instrumentation" do
    it "instruments handler execution for APM" do
      handler = TestRetryHandler.new
      allow(TestRetryHandler).to receive(:new).and_return(handler)

      events = []
      ActiveSupport::Notifications.subscribe("retry_handler_job.execute") do |name, start, finish, id, payload|
        events << payload
      end

      described_class.perform_now("TestRetryHandler", { order_id: 123 }, "Error")

      expect(events.size).to eq(1)
      expect(events.first).to include(
        handler: "TestRetryHandler",
        attempt: 1,
      )
    end
  end

  describe "job configuration" do
    it "uses default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end

    it "can be enqueued" do
      expect {
        described_class.perform_later("TestHandler", { order_id: 123 }, "Error")
      }.not_to raise_error
    end
  end
end
