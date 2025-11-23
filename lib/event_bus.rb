# frozen_string_literal: true

require "active_support"
require "active_support/notifications"
require "active_record"
require "timeout"

require_relative "event_bus/version"
require_relative "event_bus/errors"
require_relative "event_bus/configuration"
require_relative "event_bus/handler_registration"
require_relative "event_bus/middleware"
require_relative "event_bus/middleware/logging"
require_relative "event_bus/middleware/metrics"
require_relative "event_bus/middleware/transaction"
require_relative "event_bus/middleware/validation"
require_relative "event_bus/config_validator"
require_relative "event_bus/config_lister"
require_relative "event_bus/yaml_loader"
require_relative "event_bus/instrumentation"
require_relative "event_bus/railtie" if defined?(Rails::Railtie)

# Background jobs (require ActiveJob)
if defined?(ActiveJob)
  require_relative "event_bus/jobs/async_handler_job"
  require_relative "event_bus/jobs/retry_handler_job"
end

# EventBus - Enhanced in-process event dispatcher
#
# Features:
# - Middleware/Interceptor pattern for cross-cutting concerns
# - Async handlers (optional) for non-blocking side-effects
# - Handler priorities for execution order control
# - Transaction-aware publishing (defer until commit)
# - Better error handling with fallback strategies
# - Built-in instrumentation for observability
#
# @example Basic usage
#   EventBus.publish(OrderPaid.new(order_id: 123))
#
# @example With middleware
#   EventBus.use(EventBus::LoggingMiddleware.new)
#   EventBus.use(EventBus::MetricsMiddleware.new)
#
# @example Async handler
#   EventBus.subscribe(OrderPaid, SendEmailHandler.new, async: true)
#
# @example Priority handlers
#   EventBus.subscribe(OrderPaid, HighPriorityHandler.new, priority: 10)
#   EventBus.subscribe(OrderPaid, LowPriorityHandler.new, priority: 1)
#
module EventBus
  class << self
    # Registry: event_class => [HandlerRegistration]
    def handlers
      @handlers ||= Hash.new { |h, k| h[k] = [] }
    end

    def catch_all
      @catch_all ||= []
    end

    def middleware
      @middleware ||= []
    end

    # Configuration
    def configure
      yield configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end
    alias_method :config, :configuration

    # Subscribe to specific event
    #
    # @param event_class [Class] Event class to listen for
    # @param handler [#call] Handler object
    # @param priority [Integer] Execution priority (1-10, higher = earlier)
    # @param async [Boolean] Run handler asynchronously
    # @param async_priority [Symbol] Async queue priority (:critical, :high, :normal, :low)
    # @param error_strategy [Symbol] How to handle errors (:log, :raise, :retry, :ignore)
    #
    # @example
    #   EventBus.subscribe(
    #     OrderPaid,
    #     SendEmailHandler.new,
    #     priority: 8,
    #     async: false,
    #     async_priority: :normal,
    #     error_strategy: :log
    #   )
    def subscribe(event_class, handler, priority: 5, async: false, async_priority: :normal, error_strategy: :log)
      registration = HandlerRegistration.new(
        handler,
        priority: priority,
        async: async,
        async_priority: async_priority,
        error_strategy: error_strategy,
      )

      handlers[event_class] << registration
      handlers[event_class].sort_by! { |r| -r.priority } # Higher priority first

      log_subscription(event_class, handler, priority, async)
    end

    # Subscribe to all events
    def subscribe_all(handler, priority: 5, async: false, async_priority: :normal, error_strategy: :log)
      registration = HandlerRegistration.new(
        handler,
        priority: priority,
        async: async,
        async_priority: async_priority,
        error_strategy: error_strategy,
      )

      catch_all << registration
      catch_all.sort_by! { |r| -r.priority }

      log_subscription(:all, handler, priority, async)
    end

    # Add middleware (runs before handlers)
    #
    # @param middleware [Middleware] Middleware instance
    #
    # @example
    #   EventBus.use(EventBus::LoggingMiddleware.new)
    #   EventBus.use(EventBus::MetricsMiddleware.new)
    def use(new_middleware)
      raise ArgumentError, "Middleware must respond to #call" unless new_middleware.respond_to?(:call)

      middleware << new_middleware
    end

    # Publish event
    #
    # @param event [Object] Domain event
    # @param defer [Boolean, Symbol] Defer until transaction commits (default: :auto)
    #
    # @example Immediate publish
    #   EventBus.publish(OrderPaid.new(...))
    #
    # @example Defer until transaction commit
    #   EventBus.publish(OrderPaid.new(...), defer: true)
    def publish(event, defer: :auto)
      validate_event!(event)

      # Auto-detect if we're in transaction
      should_defer = defer == :auto ? in_transaction? : defer

      if should_defer
        defer_until_commit(event)
      else
        publish_now(event)
      end
    end

    # Publish immediately (bypasses transaction deferral)
    def publish_now(event)
      validate_event!(event)

      instrument("eventbus.publish", event: event.class.name) do
        # Run through middleware chain
        middleware_chain = build_middleware_chain
        middleware_chain.call(event)
      end
    rescue => e
      handle_publish_error(event, e)
      raise PublishError, "Failed to publish #{event.class.name}: #{e.message}"
    end

    # Clear all subscriptions (for testing)
    def clear!
      handlers.clear
      catch_all.clear
      middleware.clear
    end

    # Get subscribers for event (for introspection)
    def subscribers_for(event_class)
      (handlers[event_class] + catch_all).map(&:handler)
    end

    # Check if we're in ActiveRecord transaction (public API)
    def in_transaction?
      ActiveRecord::Base.connection.transaction_open?
    end

    # Get middleware chain (for introspection)
    def middleware_chain
      middleware
    end

    private

    def validate_event!(event)
      raise ArgumentError, "Event must respond to #to_h" unless event.respond_to?(:to_h)
      raise ArgumentError, "Event must respond to #partition_key" unless event.respond_to?(:partition_key)
    end

    # Defer event publishing until transaction commits
    #
    # Rails 8.0.x compatibility: Use ActiveRecord::Base.after_commit
    # (after_transaction_commit was added in Rails 8.1+)
    def defer_until_commit(event)
      # Use a lightweight approach: register callback on connection
      # In Rails 8.0, we use add_transaction_record to hook into lifecycle
      transaction_record = Object.new

      # Required methods for Rails transaction lifecycle
      def transaction_record.before_committed!; end
      def transaction_record.rolledback!(*); end
      def transaction_record.trigger_transactional_callbacks?
        true
      end

      # Store event in instance variable so callback can access it
      transaction_record.instance_variable_set(:@event_to_publish, event)
      transaction_record.instance_variable_set(:@publish_now_method, method(:publish_now))

      # Define committed! callback to publish event after transaction
      def transaction_record.committed!(*)
        event = instance_variable_get(:@event_to_publish)
        publish_method = instance_variable_get(:@publish_now_method)
        publish_method.call(event)
      end

      # Register with current transaction
      ActiveRecord::Base.connection.add_transaction_record(transaction_record)
    end

    # Build middleware chain (chain of responsibility pattern)
    def build_middleware_chain
      # Final step: execute handlers
      final_step = lambda do |event|
        execute_handlers(event)
      end

      # Build chain in reverse (last middleware wraps final_step)
      middleware.reverse.reduce(final_step) do |next_step, mw|
        lambda { |event| mw.call(event, next_step) }
      end
    end

    # Execute all handlers for event
    def execute_handlers(event)
      registrations = handlers[event.class] + catch_all
      return if registrations.empty?

      log_handlers_execution(event, registrations.size)

      registrations.each do |registration|
        execute_handler_with_strategy(registration, event)
      end
    end

    # Execute single handler with error strategy
    def execute_handler_with_strategy(registration, event)
      Timeout.timeout(configuration.max_handler_time) do
        registration.call(event)
      end
    rescue Timeout::Error => e
      handle_handler_error(registration, event, e, "Handler timeout")
    rescue => e
      handle_handler_error(registration, event, e)
    end

    # Handle handler errors based on strategy
    def handle_handler_error(registration, event, error, message = nil)
      case registration.error_strategy
      when :raise
        raise HandlerError, "Handler #{registration.handler.class.name} failed: #{error.message}"
      when :retry
        # Queue for retry (requires ActiveJob)
        if defined?(ActiveJob)
          EventBus::Jobs::RetryHandlerJob.perform_later(
            registration.handler.class.name,
            event.to_h,
            error.message,
          )
        else
          log_handler_error(registration.handler, event, error, "Retry strategy requires ActiveJob")
        end
      when :log
        log_handler_error(registration.handler, event, error, message)
      when :ignore
        # Silently ignore
      end

      # Always send to instrumentation
      instrument_handler_error(registration.handler, event, error)
    end

    # Instrumentation (ActiveSupport::Notifications)
    def instrument(name, payload = {})
      if configuration.enable_instrumentation
        ActiveSupport::Notifications.instrument(name, payload) do
          yield if block_given?
        end
      elsif block_given?
        yield
      end
    end

    def instrument_handler_error(handler, event, error)
      instrument(
        "eventbus.handler_error",
        handler: handler.class.name,
        event: event.class.name,
        error_class: error.class.name,
        error_message: error.message,
        exception: error, # Full exception object for error reporters
        event_payload: event.to_h,
        backtrace: error.backtrace&.first(10),
      )
    end

    # Logging
    def log_subscription(event_class, handler, priority, async)
      attributes = {
        event_class: event_class.to_s,
        handler: handler.class.name,
        priority: priority,
        async: async
      }
      logger.debug("EventBus-#{EventBus::VERSION} Handler subscribed  #{format_log_attributes(**attributes)}")
    end

    def log_handlers_execution(event, count)
      attributes = {
        event_class: event.class.name,
        handlers_count: count
      }
      logger.debug("EventBus-#{EventBus::VERSION} Publishing event  #{format_log_attributes(**attributes)}")
    end

    def log_handler_error(handler, event, error, message = nil)
      attributes = {
        handler: handler.class.name,
        event_class: event.class.name,
        error: error.message
      }
      attributes[:custom_message] = message if message
      attributes[:backtrace] = error.backtrace&.first(5)

      logger.error("EventBus-#{EventBus::VERSION} Handler error  #{format_log_attributes(**attributes)}")
    end

    def handle_publish_error(event, error)
      attributes = {
        event_class: event.class.name,
        error: error.message,
        backtrace: error.backtrace&.first(5)
      }
      logger.error("EventBus-#{EventBus::VERSION} Publish error  #{format_log_attributes(**attributes)}")
    end

    def format_log_attributes(**attributes)
      attributes.map { |attr, value| "#{attr}: #{value.inspect}" }.join(", ")
    end

    def logger
      configuration.logger
    end
  end
end
