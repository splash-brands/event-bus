# frozen_string_literal: true

module EventBus
  # Configuration object for EventBus
  #
  # @example Basic configuration
  #   EventBus.configure do |config|
    #     config.log_level = :info
  #     config.persist_to_outbox = true
  #     config.max_handler_time = 10.seconds
  #   end
  #
  class Configuration
    attr_accessor :log_level,
                  :persist_to_outbox,
                  :raise_handler_errors,
                  :max_handler_time,
                  :enable_instrumentation,
                  :logger,
                  :pack_namespace_mapping,
                  :default_async,
                  :async_queue,
                  :async_priorities

    def initialize
      @log_level = :debug
      @persist_to_outbox = true
      @raise_handler_errors = false
      @max_handler_time = 5 # seconds
      @enable_instrumentation = true
      @logger = nil # Will use Rails.logger if available
      @pack_namespace_mapping = {}

      # Async-first mode configuration
      @default_async = false # Default to sync for backward compatibility
      @async_queue = :eventbus_handlers # Default Sidekiq queue name
      @async_priorities = {
        critical: 10, # Email notifications, alerts
        high: 8,      # Operator notifications
        normal: 5,    # Cache updates, logging
        low: 3,       # Analytics, reporting
      }
    end

    # Get configured or default logger
    def logger
      @logger || default_logger
    end

    private

    def default_logger
      if defined?(Rails) && Rails.respond_to?(:logger)
        Rails.logger
      else
        require "logger"
        Logger.new($stdout)
      end
    end
  end
end
