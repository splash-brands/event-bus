# frozen_string_literal: true

module EventBus
  # Metrics middleware (Datadog)
  #
  # Sends event metrics to Datadog Statsd if available.
  #
  # Metrics sent:
  # - eventbus.published - Counter for each event published
  # - eventbus.duration - Histogram of event processing time
  #
  # @example
  #   EventBus.use(EventBus::MetricsMiddleware.new)
  #
  class MetricsMiddleware < Middleware
      def call(event, next_middleware)
        start = Time.current

        result = next_middleware.call(event)

        duration = Time.current - start

        if defined?(Datadog::Statsd)
          statsd = Datadog::Statsd.new
          statsd.increment("eventbus.published", tags: ["event:#{event.class.name}"])
          statsd.histogram("eventbus.duration", duration, tags: ["event:#{event.class.name}"])
        end

        result
      end
  end
end
