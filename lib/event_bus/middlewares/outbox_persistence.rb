# frozen_string_literal: true

module EventBus
  module Middlewares
    # OutboxPersistence middleware integrates EventBus with persistence backends
    # (like OutboxRelay, Kafka, SQS) for reliable cross-process event delivery.
    #
    # This middleware uses the Transactional Outbox Pattern:
    # 1. Execute in-process handlers synchronously first
    # 2. Persist events to outbox in the same database transaction
    # 3. Background workers asynchronously publish to message broker
    #
    # Architecture:
    # - Adapter Pattern: Supports any persistence backend (OutboxRelay, Kafka, etc.)
    # - Config Loader: Determines which events to persist (from events.yml)
    # - Failure Handling: Logs errors but doesn't fail handler execution
    #
    # @example Basic usage with OutboxRelay
    #   adapter = EventBus::Adapters::OutboxRelayAdapter.new(OutboxPublisher)
    #   config_loader = EventBus::PackConfigLoader.new(Rails.root)
    #
    #   EventBus.use(
    #     EventBus::Middleware::OutboxPersistence.new(
    #       adapter: adapter,
    #       config_loader: config_loader,
    #       logger: Rails.logger
    #     )
    #   )
    #
    # @example Custom adapter
    #   class MyKafkaAdapter
    #     def publish(topic:, payload:, headers:)
    #       Kafka.producer.produce(payload, topic: topic, headers: headers)
    #     end
    #   end
    #
    #   EventBus.use(
    #     EventBus::Middleware::OutboxPersistence.new(
    #       adapter: MyKafkaAdapter.new,
    #       config_loader: config_loader
    #     )
    #   )
    class OutboxPersistence
      attr_reader :adapter, :config_loader, :logger

      # @param adapter [Object] Persistence backend adapter (must respond to #publish)
      # @param config_loader [Object] Configuration loader (must respond to #should_persist? and #pack_name_for)
      # @param logger [Logger, nil] Optional logger for errors (defaults to EventBus.configuration.logger)
      def initialize(adapter:, config_loader:, logger: nil)
        @adapter = adapter
        @config_loader = config_loader
        @logger = logger || EventBus.configuration.logger
      end

      # Middleware execution:
      # 1. Execute in-process handlers first (synchronous)
      # 2. Persist to outbox if configured (cross-process delivery)
      #
      # @param event [Object] Event instance (must respond to #to_h and #partition_key)
      # @param next_middleware [Proc] Next middleware in chain
      def call(event, next_middleware)
        # Execute handlers synchronously first
        next_middleware.call(event)

        # Persist to outbox if configured (for cross-process delivery)
        persist_to_outbox(event) if should_persist?(event)
      end

      private

      # Check if event should be persisted to outbox
      #
      # @param event [Object] Event instance
      # @return [Boolean] true if event is configured to persist
      def should_persist?(event)
        config_loader.should_persist?(event)
      end

      # Persist event to outbox using configured adapter
      #
      # Failures are logged but don't stop execution - in-process handlers
      # already executed successfully, so we don't want to fail the request.
      #
      # @param event [Object] Event instance
      def persist_to_outbox(event)
        pack_name = config_loader.pack_name_for(event)

        adapter.publish(
          topic: determine_topic(pack_name),
          payload: event.to_h,
          headers: {
            event_name: event_name_from_class(event),
            partition_key: event.partition_key,
          },
        )
      rescue => e
        logger&.error(
          event: "eventbus.outbox_persistence_failed",
          event_class: event.class.name,
          error: e.message,
          backtrace: e.backtrace&.first(5),
        )
        # Don't raise - let handlers execute even if outbox fails
      end

      # Determine Kafka topic from pack name
      #
      # Convention: {pack_directory}_updates
      # Example: embroidery pack → embroidery_updates
      #          orders pack → orders_updates
      #
      # @param pack_name [String] Pack directory name (e.g., "embroidery", "orders")
      # @return [String] Kafka topic name
      def determine_topic(pack_name)
        "#{pack_name}_updates"
      end

      # Extract event name from event class
      #
      # Converts: Orders::Events::OrderPaid → order_paid
      #           EmbNeedles::Events::ThreadUpdated → thread_updated
      #
      # @param event [Object] Event instance
      # @return [String] Underscored event name
      def event_name_from_class(event)
        event.class.name.demodulize.underscore
      end
    end
  end
end
