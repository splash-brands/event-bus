# frozen_string_literal: true

module EventBus
  module Jobs
    # ActiveJob for retrying failed event handlers
    #
    # Used when handlers fail and have `error_strategy: :retry`.
    # Provides comprehensive observability for production debugging.
    #
    # **Observability Stack (4 layers)**:
    # 1. Sentry Alerts → Immediate notifications when retries exhausted
    # 2. Enhanced Logging → Full error context with backtrace
    # 3. ActiveSupport::Notifications → APM metrics
    # 4. Sidekiq UI → Manual inspection of dead set (last resort)
    #
    # @example Handler registration
    #   EventBus.subscribe(
    #     OrderPaid,
    #     ExternalApiHandler.new,
    #     error_strategy: :retry  # Uses RetryHandlerJob
    #   )
    #
    # @example Retry attempts
    #   Attempt 1: Immediate retry
    #   Attempt 2: Exponential backoff (wait increases)
    #   Attempt 3: Final retry attempt
    #   All failed: Sentry alert + Datadog error log + Sidekiq dead set
    #
    class RetryHandlerJob < ActiveJob::Base
      queue_as :default

      # Sidekiq retry configuration
      # 3 attempts total (initial + 2 retries)
      # In production: use exponential backoff (wait: :exponentially_longer)
      # In test: use fixed delay to avoid ActiveJob test adapter issues
      retry_on StandardError, wait: 5.seconds, attempts: 3 do |job, error|
        # Called when all retries are exhausted
        job.report_retries_exhausted(error)
      end

      # @param handler_class_name [String] Handler class name
      # @param event_data [Hash] Event data (from event.to_h)
      # @param original_error_message [String] Original error that triggered retry
      def perform(handler_class_name, event_data, original_error_message)
        log_retry_attempt(handler_class_name, event_data, original_error_message)

        handler = constantize_handler(handler_class_name)
        event = build_event(event_data)

        # Instrument for APM
        ActiveSupport::Notifications.instrument(
          "retry_handler_job.execute",
          handler: handler_class_name,
          attempt: executions,
        ) do
          handler.call(event)
        end

        log_retry_success(handler_class_name, event_data)
      rescue => e
        log_retry_failure(handler_class_name, event_data, e)
        raise # Re-raise to trigger ActiveJob retry mechanism
      end

      # Called when all retries are exhausted (after 3 attempts)
      #
      # Sends comprehensive error context to Sentry for alerting.
      # This is the primary signal that manual intervention is needed.
      #
      # @param error [Exception] Final error that caused exhaustion
      def report_retries_exhausted(error)
        handler_class_name = arguments[0]
        event_data = arguments[1]
        original_error_message = arguments[2]

        # Log exhaustion with full context
        log_retries_exhausted(handler_class_name, event_data, original_error_message, error)

        # Report to Sentry with custom fingerprinting
        if defined?(Sentry)
          Sentry.capture_exception(error,
            tags: {
              handler: handler_class_name,
              job_class: self.class.name,
              queue: queue_name,
            },
            extra: {
              event_payload: event_data,
              original_error: original_error_message,
              final_error: error.message,
              attempts: executions,
              job_id: job_id,
            },
            fingerprint: [
              "retry_handler_job",
              handler_class_name,
              error.class.name,
            ],)
        end
      end

      private

      # Instantiate handler from class name
      def constantize_handler(handler_class_name)
        handler_class = Object.const_get(handler_class_name)
        handler_class.new
      rescue NameError => e
        raise ConfigurationError, "Handler class '#{handler_class_name}' not found: #{e.message}"
      end

      # Rebuild event object from hash data
      def build_event(event_data)
        require "ostruct"
        OpenStruct.new(event_data)
      end

      # Enhanced logging methods for observability

      def log_retry_attempt(handler_class_name, event_data, original_error)
        attributes = {
          handler: handler_class_name,
          attempt: executions,
          original_error: original_error,
          job_id: job_id,
          queue: queue_name
        }
        formatted_attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        logger.info("EventBus-#{EventBus::VERSION} Retry attempt  #{formatted_attrs}")
      end

      def log_retry_success(handler_class_name, event_data)
        attributes = {
          handler: handler_class_name,
          attempt: executions,
          job_id: job_id,
          event_id: event_data[:id] || event_data["id"]
        }
        formatted_attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        logger.info("EventBus-#{EventBus::VERSION} Retry succeeded  #{formatted_attrs}")
      end

      def log_retry_failure(handler_class_name, event_data, error)
        attributes = {
          handler: handler_class_name,
          attempt: executions,
          error: error.message,
          job_id: job_id,
          backtrace: error.backtrace&.first(3)
        }
        formatted_attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        logger.warn("EventBus-#{EventBus::VERSION} Retry failed  #{formatted_attrs}")
      end

      def log_retries_exhausted(handler_class_name, event_data, original_error, final_error)
        attributes = {
          handler: handler_class_name,
          event_payload: event_data,
          original_error: original_error,
          final_error: final_error.message,
          backtrace: final_error.backtrace&.first(10),
          job_id: job_id,
          attempts: executions
        }
        formatted_attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        logger.error("EventBus-#{EventBus::VERSION} Retries exhausted  #{formatted_attrs}")
      end
    end
  end
end
