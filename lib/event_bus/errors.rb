# frozen_string_literal: true

module EventBus
  # Base error class for all EventBus errors
  class Error < StandardError; end

  # Raised when event publishing fails
  class PublishError < Error; end

  # Raised when handler execution fails (if error_strategy is :raise)
  class HandlerError < Error; end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end
end
