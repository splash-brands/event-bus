# frozen_string_literal: true

require "rails/railtie"

module EventBus
  # Rails integration
  #
  # Automatically loads EventBus configuration and initializes the gem
  # when used in a Rails application.
  #
  # @example Configuration in config/initializers/event_bus.rb
  #   EventBus.configure do |config|
  #     config.log_level = :info
  #     config.persist_to_outbox = true
  #     config.max_handler_time = 10
  #   end
  #
  #   # Add middleware
  #   EventBus.use(EventBus::Middleware::Logging.new)
  #   EventBus.use(EventBus::Middleware::Metrics.new)
  #
  class Railtie < Rails::Railtie
    # Load rake tasks
    rake_tasks do
      load File.expand_path("../tasks/eventbus.rake", __dir__)
    end

    # Load EventBus configuration from Rails
    initializer "event_bus.configure" do |app|
      # Make configuration available at Rails.application.config.event_bus
      app.config.event_bus = EventBus.configuration

      # Set default logger to Rails logger
      EventBus.configuration.logger ||= Rails.logger
    end

    # Clear subscriptions in test environment between runs
    initializer "event_bus.clear_test_subscriptions" do |app|
      if Rails.env.test?
        # Clear before each test suite run
        app.config.after_initialize do
          EventBus.clear! if defined?(RSpec)
        end
      end
    end

    # Log EventBus initialization
    initializer "event_bus.log_initialization", after: :load_config_initializers do
      Rails.logger.info "EventBus-#{EventBus::VERSION} Initialized  event_types: #{EventBus.handlers.size}"
    end
  end
end
