# frozen_string_literal: true

module EventBus
  # Middleware base class
  #
  # Middleware allows you to intercept events before they reach handlers.
  # Each middleware must implement #call(event, next_middleware) and invoke
  # next_middleware.call(event) to continue the chain.
  #
  # @example Custom middleware
  #   class TimingMiddleware < EventBus::Middleware
  #     def call(event, next_middleware)
  #       start = Time.current
  #       result = next_middleware.call(event)
  #       duration = Time.current - start
  #       puts "Event processed in #{duration}s"
  #       result
  #     end
  #   end
  #
  class Middleware
    def call(event, next_middleware)
      # Override this method in subclasses
      # Example:
      #   log("Before: #{event.class}")
      #   result = next_middleware.call(event)
      #   log("After: #{event.class}")
      #   result
      raise NotImplementedError, "Middleware must implement #call(event, next_middleware)"
    end
  end
end
