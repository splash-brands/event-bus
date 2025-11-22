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
                  :pack_namespace_mapping

    def initialize
      @log_level = :debug
      @persist_to_outbox = true
      @raise_handler_errors = false
      @max_handler_time = 5 # seconds
      @enable_instrumentation = true
      @logger = nil # Will use Rails.logger if available
      @pack_namespace_mapping = {}
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
