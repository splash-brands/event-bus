# frozen_string_literal: true

module EventBus
  # Validation middleware
  #
  # Validates events before publishing if they respond to #valid?
  # Raises PublishError if event is invalid.
  #
  # @example
  #   EventBus.use(EventBus::ValidationMiddleware.new)
  #
  # @example Event with validation
  #   class OrderPaid
  #     include ActiveModel::Validations
  #
  #     validates :order_id, presence: true
  #
  #     def initialize(order_id:)
  #       @order_id = order_id
  #     end
  #
  #     def valid?
  #       super
  #     end
  #   end
  #
  class ValidationMiddleware < Middleware
      def call(event, next_middleware)
        # Validate event payload if it responds to #valid?
        if event.respond_to?(:valid?) && !event.valid?
          errors = event.respond_to?(:errors) ? event.errors.full_messages.join(", ") : "validation failed"
          raise EventBus::PublishError, "Invalid event: #{errors}"
        end

        next_middleware.call(event)
      end
  end
end
