# frozen_string_literal: true

require "active_support/notifications"

module EventBus
  # Instrumentation module for EventBus observability
  #
  # EventBus emits observability events using ActiveSupport::Notifications.
  # Applications can subscribe to these events and route them to their
  # monitoring backend of choice (Sentry, Datadog, New Relic, etc.).
  #
  # ## Available Events
  #
  # ### eventbus.handler_error
  # Emitted when a handler raises an error (regardless of error_strategy)
  #
  # **Payload**:
  # - `handler` (String) - Handler class name
  # - `event` (String) - Event class name
  # - `error_class` (String) - Error class name
  # - `error_message` (String) - Error message
  # - `exception` (Exception) - Full exception object
  # - `event_payload` (Hash) - Event data (from event.to_h)
  # - `backtrace` (Array<String>) - First 10 lines of backtrace
  #
  # @example Subscribe to all EventBus errors and send to Sentry
  #   ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #     Sentry.capture_exception(
  #       payload[:exception],
  #       extra: {
  #         handler: payload[:handler],
  #         event: payload[:event],
  #         event_payload: payload[:event_payload]
  #       },
  #       tags: {
  #         component: "event_bus",
  #         handler: payload[:handler]
  #       }
  #     )
  #   end
  #
  # @example Subscribe to all EventBus errors and send to Datadog
  #   ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #     Datadog::Statsd.new.increment(
  #       "eventbus.handler.error",
  #       tags: [
  #         "handler:#{payload[:handler]}",
  #         "event:#{payload[:event]}",
  #         "error:#{payload[:error_class]}"
  #       ]
  #     )
  #   end
  #
  # @example Pattern matching on specific handlers
  #   ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #     case payload[:handler]
  #     when "AuditHandler"
  #       # Critical - page on-call
  #       PagerDuty.trigger(payload[:exception])
  #     when "CacheUpdateHandler"
  #       # Non-critical - just log
  #       Rails.logger.warn("Cache update failed: #{payload[:error_message]}")
  #     else
  #       # Default - send to Sentry
  #       Sentry.capture_exception(payload[:exception])
  #     end
  #   end
  #
  # ### eventbus.publish
  # Emitted when an event is published (before middleware/handlers run)
  #
  # **Payload**:
  # - `event` (String) - Event class name
  #
  # @example Count published events
  #   ActiveSupport::Notifications.subscribe("eventbus.publish") do |name, start, finish, id, payload|
  #     Datadog::Statsd.new.increment("eventbus.events.published", tags: ["event:#{payload[:event]}"])
  #   end
  #
  # ## Integration Patterns
  #
  # ### Sentry Integration (Recommended)
  #
  # Add to `config/initializers/event_bus.rb`:
  #
  # ```ruby
  # if defined?(Sentry)
  #   ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #     Sentry.capture_exception(
  #       payload[:exception],
  #       extra: payload.except(:exception),
  #       tags: { component: "event_bus", handler: payload[:handler] },
  #       fingerprint: ["eventbus", payload[:handler], payload[:error_class]]
  #     )
  #   end
  # end
  # ```
  #
  # ### Datadog Integration
  #
  # Add to `config/initializers/event_bus.rb`:
  #
  # ```ruby
  # if defined?(Datadog)
  #   # Error metrics
  #   ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #     Datadog::Statsd.new.increment(
  #       "eventbus.handler.error",
  #       tags: ["handler:#{payload[:handler]}", "event:#{payload[:event]}"]
  #     )
  #   end
  #
  #   # Publish metrics
  #   ActiveSupport::Notifications.subscribe("eventbus.publish") do |name, start, finish, id, payload|
  #     duration = finish - start
  #     Datadog::Statsd.new.timing("eventbus.publish.duration", duration, tags: ["event:#{payload[:event]}"])
  #   end
  # end
  # ```
  #
  # ### Custom Logger Integration
  #
  # ```ruby
  # ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #   Rails.application.config.custom_logger.error(
  #     event_name: "event_bus_handler_error",
  #     handler: payload[:handler],
  #     event: payload[:event],
  #     error: payload[:error_message],
  #     backtrace: payload[:backtrace]
  #   )
  # end
  # ```
  #
  # ## Testing
  #
  # In tests, you can subscribe to notifications to verify behavior:
  #
  # ```ruby
  # RSpec.describe MyHandler do
  #   it "emits error notification on failure" do
  #     errors = []
  #     subscription = ActiveSupport::Notifications.subscribe("eventbus.handler_error") do |name, start, finish, id, payload|
  #       errors << payload
  #     end
  #
  #     EventBus.publish(MyEvent.new)
  #
  #     expect(errors.size).to eq(1)
  #     expect(errors.first[:handler]).to eq("MyHandler")
  #
  #     ActiveSupport::Notifications.unsubscribe(subscription)
  #   end
  # end
  # ```
  #
  # ## Best Practices
  #
  # 1. **Subscribe in initializer** - Set up subscriptions in `config/initializers/event_bus.rb`
  # 2. **Use fingerprinting** - Group similar errors in Sentry with custom fingerprints
  # 3. **Add context** - Include handler name, event type as tags for filtering
  # 4. **Avoid re-raising** - Subscriptions should not raise errors (they'll be silently ignored)
  # 5. **Keep it fast** - Notification callbacks should be lightweight (< 10ms)
  #
  module Instrumentation
    # This module is intentionally empty - it serves as documentation.
    # EventBus uses ActiveSupport::Notifications directly in the main module.
    #
    # See EventBus#instrument and EventBus#instrument_handler_error for implementation.
  end
end
