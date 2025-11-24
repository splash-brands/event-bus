# frozen_string_literal: true

module EventBus
  # Logging middleware
  #
  # Logs event publishing with timing information following SolidQueue's format.
  #
  # @example
  #   EventBus.use(EventBus::LoggingMiddleware.new)
  #
  class LoggingMiddleware < Middleware
      def call(event, next_middleware)
        start = Time.current

        result = next_middleware.call(event)

        duration = ((Time.current - start) * 1000).round(1)
        logger.debug("EventBus-#{EventBus::VERSION} Published event (#{duration}ms)  event: #{event.class.name}")

        result
      end

      private

      def logger
        EventBus.configuration.logger
      end
  end
end
