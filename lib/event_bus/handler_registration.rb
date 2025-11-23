# frozen_string_literal: true

module EventBus
  # Handler wrapper with metadata
  #
  # Wraps a handler object with metadata about priority, async execution,
  # and error handling strategy.
  #
  # @example
  #   registration = HandlerRegistration.new(
  #     MyHandler.new,
  #     priority: 8,
  #     async: false,
  #     error_strategy: :log
  #   )
  #   registration.call(event)
  #
  class HandlerRegistration
    attr_reader :handler, :priority, :async, :async_priority, :error_strategy

    # @param handler [#call] Handler object that responds to #call(event)
    # @param priority [Integer] Execution priority (1-10, higher = earlier)
    # @param async [Boolean] Run handler asynchronously
    # @param async_priority [Symbol] Async queue priority (:critical, :high, :normal, :low)
    # @param error_strategy [Symbol] Error handling strategy (:log, :raise, :retry, :ignore)
    def initialize(handler, priority: 5, async: false, async_priority: :normal, error_strategy: :log)
      @handler = handler
      @priority = priority
      @async = async
      @async_priority = async_priority
      @error_strategy = error_strategy

      validate!
    end

    # Execute the handler
    #
    # If async is true, queues the handler for background execution.
    # Otherwise, calls the handler immediately.
    #
    # @param event [Object] Event to pass to handler
    def call(event)
      if async
        # Run in background (requires Rails ActiveJob)
        require_active_job!

        # Determine Sidekiq queue based on async_priority
        queue_name = determine_queue_name

        EventBus::Jobs::AsyncHandlerJob.set(queue: queue_name).perform_later(
          handler.class.name,
          event.to_h,
        )
      else
        handler.call(event)
      end
    end

    private

    def validate!
      raise ArgumentError, "Handler must respond to #call" unless handler.respond_to?(:call)
      raise ArgumentError, "Priority must be 1-10" unless (1..10).cover?(priority)
      raise ArgumentError, "Invalid error_strategy" unless [:log, :raise, :retry, :ignore].include?(error_strategy)
      raise ArgumentError, "Invalid async_priority" unless [:critical, :high, :normal, :low].include?(async_priority)
    end

    def require_active_job!
      return if defined?(ActiveJob)

      raise ConfigurationError, "Async handlers require ActiveJob (Rails). " \
                                "Either disable async: true or add ActiveJob to your application."
    end

    # Determine Sidekiq queue name based on async_priority
    # Maps priority levels to actual queue names
    #
    # @return [Symbol] Queue name
    def determine_queue_name
      # Use configured base queue name + priority suffix
      # e.g., :eventbus_handlers_critical, :eventbus_handlers_normal
      base_queue = EventBus.configuration.async_queue
      "#{base_queue}_#{async_priority}".to_sym
    end
  end
end
