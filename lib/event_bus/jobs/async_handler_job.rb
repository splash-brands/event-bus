# frozen_string_literal: true

module EventBus
  module Jobs
    # ActiveJob for executing event handlers asynchronously
    #
    # Used when handlers are registered with `async: true`.
    # Allows non-blocking side effects and background processing.
    #
    # @example Handler registration
    #   EventBus.subscribe(
    #     OrderPaid,
    #     SendEmailHandler.new,
    #     async: true  # Uses AsyncHandlerJob
    #   )
    #
    # @example Job execution
    #   AsyncHandlerJob.perform_later("SendEmailHandler", { order_id: 123 })
    #
    class AsyncHandlerJob < ActiveJob::Base
      queue_as :default

      # @param handler_class_name [String] Handler class name
      # @param event_data [Hash] Event data (from event.to_h)
      def perform(handler_class_name, event_data)
        handler = constantize_handler(handler_class_name)
        event = build_event(event_data)

        handler.call(event)
      rescue => e
        log_error(handler_class_name, event_data, e)
        raise # Re-raise to trigger ActiveJob retry mechanism
      end

      private

      # Instantiate handler from class name
      #
      # @param handler_class_name [String] Handler class name
      # @return [Object] Handler instance
      def constantize_handler(handler_class_name)
        handler_class = Object.const_get(handler_class_name)
        handler_class.new
      rescue NameError => e
        raise ConfigurationError, "Handler class '#{handler_class_name}' not found: #{e.message}"
      end

      # Rebuild event object from hash data
      #
      # Events are serialized as hashes for job queues.
      # This reconstructs a simple event object with the data.
      #
      # @param event_data [Hash] Event data
      # @return [OpenStruct] Event-like object
      def build_event(event_data)
        require "ostruct"
        OpenStruct.new(event_data)
      end

      # Log error for observability
      def log_error(handler_class_name, event_data, error)
        attributes = {
          handler: handler_class_name,
          event_data: event_data,
          error: error.message,
          backtrace: error.backtrace&.first(5)
        }
        formatted_attrs = attributes.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
        logger.error("EventBus-#{EventBus::VERSION} Async handler error  #{formatted_attrs}")
      end
    end
  end
end
