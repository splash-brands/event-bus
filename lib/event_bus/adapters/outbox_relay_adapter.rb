# frozen_string_literal: true

module EventBus
  module Adapters
    # Adapter for OutboxRelay gem integration.
    #
    # OutboxRelay implements the Transactional Outbox Pattern:
    # - Events written to database table in same transaction as business logic
    # - Background workers asynchronously publish to Kafka
    # - Guarantees at-least-once delivery (no message loss on rollback)
    #
    # This adapter wraps OutboxPublisher from the OutboxRelay gem.
    #
    # @example Setup in Rails application
    #   # config/initializers/event_bus.rb
    #   adapter = EventBus::Adapters::OutboxRelayAdapter.new(OutboxPublisher)
    #   config_loader = EventBus::PackConfigLoader.new(Rails.root)
    #
    #   EventBus.use(
    #     EventBus::Middleware::OutboxPersistence.new(
    #       adapter: adapter,
    #       config_loader: config_loader
    #     )
    #   )
    class OutboxRelayAdapter < BaseAdapter
      attr_reader :publisher

      # @param publisher [Class] OutboxPublisher class from OutboxRelay gem
      def initialize(publisher)
        @publisher = publisher
      end

      # Publish event to OutboxRelay.
      #
      # OutboxPublisher.publish writes to outbox_relay_outbox_events table
      # in the current database transaction. Background workers (bin/outbox_relay)
      # then publish to Kafka asynchronously.
      #
      # @param topic [String] Kafka topic name
      # @param payload [Hash] Event data (will be stored as JSONB)
      # @param headers [Hash] Event metadata (event_name, partition_key)
      # @return [OutboxRelay::OutboxEvent] Created outbox event record
      def publish(topic:, payload:, headers:)
        publisher.publish(
          topic: topic,
          payload: payload,
          headers: headers,
        )
      end
    end
  end
end
