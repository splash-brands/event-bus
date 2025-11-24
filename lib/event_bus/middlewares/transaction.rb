# frozen_string_literal: true

module EventBus
  # Transaction tracking middleware
  #
  # Logs when events are published inside ActiveRecord transactions.
  # Useful for debugging and monitoring transaction-aware behavior.
  #
  # @example
  #   EventBus.use(EventBus::TransactionMiddleware.new)
  #
  class TransactionMiddleware < Middleware
      def call(event, next_middleware)
        if ActiveRecord::Base.connection.transaction_open?
          logger.debug("EventBus-#{EventBus::VERSION} Publishing inside transaction  event: #{event.class.name.inspect}")
        end

        next_middleware.call(event)
      end

      private

      def logger
        EventBus.configuration.logger
      end
  end
end
