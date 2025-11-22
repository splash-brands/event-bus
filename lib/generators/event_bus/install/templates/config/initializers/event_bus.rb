# frozen_string_literal: true

# EventBus Configuration
#
# EventBus is a lightweight in-process event dispatcher with middleware support,
# transaction awareness, and async handler execution.
#
# Documentation: https://github.com/splash-brands/event-bus

Rails.application.config.to_prepare do
  # ============================================================================
  # EventBus Configuration
  # ============================================================================

  EventBus.configure do |config|
    # Maximum time a handler can run before timeout (default: 5 seconds)
    # Prevents slow handlers from blocking the request
    config.max_handler_time = 5.seconds

    # Enable ActiveSupport::Notifications instrumentation (default: true)
    # Required for APM integration (Datadog, New Relic, etc.)
    config.enable_instrumentation = true

    # Logger for EventBus internal logging (default: Rails.logger)
    config.logger = Rails.logger
  end

  # ============================================================================
  # Middleware Chain (Chain of Responsibility Pattern)
  # ============================================================================
  #
  # Middleware executes in order before event handlers run.
  # Each middleware can:
  # - Log, measure, or modify events
  # - Short-circuit execution
  # - Add cross-cutting concerns
  #
  # Built-in middleware:
  # - LoggingMiddleware: Logs event publishing with timing
  # - MetricsMiddleware: Tracks metrics for APM
  # - TransactionMiddleware: Warns if publishing inside transaction
  # - ValidationMiddleware: Validates event structure
  #
  # Example custom middleware:
  #   class MyMiddleware
  #     def call(event, next_middleware)
  #       # Do something before handlers
  #       result = next_middleware.call(event)
  #       # Do something after handlers
  #       result
  #     end
  #   end
  #
  #   EventBus.use(MyMiddleware.new)

  # 1. Logging Middleware - Log event publishing
  EventBus.use(EventBus::LoggingMiddleware.new)

  # 2. Metrics Middleware - Track metrics in APM
  EventBus.use(EventBus::MetricsMiddleware.new)

  # 3. Transaction Middleware - Warn if publishing inside transaction without deferral
  EventBus.use(EventBus::TransactionMiddleware.new)

  # 4. Validation Middleware - Validate event structure (optional, adds overhead)
  # EventBus.use(EventBus::ValidationMiddleware.new)

  # ============================================================================
  # Event Handlers
  # ============================================================================
  #
  # Subscribe handlers to events using EventBus.subscribe:
  #
  #   EventBus.subscribe(
  #     MyEvent,                    # Event class
  #     MyHandler.new,              # Handler instance
  #     priority: 5,                # Execution order (1-10, higher = earlier)
  #     async: false,               # Run in background job?
  #     error_strategy: :log        # :log, :raise, :retry, or :ignore
  #   )
  #
  # Handler requirements:
  # - Must respond to #call(event)
  # - Event must respond to #to_h and #partition_key
  #
  # Example handler:
  #   class SendEmailHandler
  #     def call(event)
  #       UserMailer.order_confirmation(event.order_id).deliver_later
  #     end
  #   end
  #
  # Load your handlers here or in separate initializers:
  # Dir[Rails.root.join("app/events/handlers/**/*.rb")].each { |f| require f }

  Rails.logger.info "EventBus-#{EventBus::VERSION} Initialized"
end
