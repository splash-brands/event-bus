# frozen_string_literal: true

module EventBus
  module Adapters
    # Base adapter interface for persistence backends.
    #
    # All persistence adapters must implement the #publish method with this signature.
    # This allows OutboxPersistence middleware to work with any backend:
    # - OutboxRelay (transactional outbox pattern)
    # - Direct Kafka publishing
    # - AWS SQS/SNS
    # - RabbitMQ
    # - Custom message brokers
    #
    # @example Implementing a custom adapter
    #   class MyKafkaAdapter < EventBus::Adapters::BaseAdapter
    #     def initialize(kafka_producer)
    #       @producer = kafka_producer
    #     end
    #
    #     def publish(topic:, payload:, headers:)
    #       @producer.produce(
    #         payload.to_json,
    #         topic: topic,
    #         headers: headers
    #       )
    #     end
    #   end
    class BaseAdapter
      # Publish event to persistence backend.
      #
      # @param topic [String] Destination topic/queue name
      # @param payload [Hash] Event payload (already serialized via event.to_h)
      # @param headers [Hash] Event metadata (event_name, partition_key, etc.)
      # @raise [NotImplementedError] Must be implemented by subclasses
      def publish(topic:, payload:, headers:)
        raise NotImplementedError, "#{self.class}#publish must be implemented"
      end
    end
  end
end
