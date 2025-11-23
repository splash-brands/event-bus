# frozen_string_literal: true

require "yaml"

module EventBus
  # Loads and registers event handlers from YAML configuration files
  #
  # Searches for event_handlers.yml in all Rails pack directories and main config.
  # Automatically registers handlers with EventBus on Rails boot.
  #
  # YAML Structure:
  #   events:
  #     event_name:
  #       event_class: "Full::Class::Name"
  #       description: "Event description"
  #       handlers:
  #         - name: "HandlerName"
  #           class: "Full::Handler::ClassName"
  #           priority: 10
  #           async: false
  #           error_strategy: log
  #           description: "Handler description"
  #
  # @example Load handlers from all packs
  #   EventBus::YamlLoader.load_all
  #
  # @example Load from specific file
  #   EventBus::YamlLoader.load_file("packs/workflow/config/event_handlers.yml")
  #
  class YamlLoader
    class << self
      # Load handlers from all YAML configuration files
      #
      # Searches in:
      # 1. config/event_handlers.yml (main app config)
      # 2. packs/*/config/event_handlers.yml (all pack configs)
      #
      # @return [Hash] Statistics about loaded handlers
      def load_all
        stats = { files: 0, events: 0, handlers: 0, errors: [] }

        config_files.each do |file_path|
          begin
            result = load_file(file_path)
            stats[:files] += 1
            stats[:events] += result[:events]
            stats[:handlers] += result[:handlers]
          rescue => e
            stats[:errors] << { file: file_path, error: e.message }
          end
        end

        log_loading_stats(stats)
        stats
      end

      # Load handlers from a specific YAML file
      #
      # @param file_path [String] Path to YAML file
      # @return [Hash] Statistics about loaded handlers from this file
      def load_file(file_path)
        return { events: 0, handlers: 0 } unless File.exist?(file_path)

        config = YAML.safe_load_file(
          file_path,
          permitted_classes: [Symbol],
          symbolize_names: true,
        )

        return { events: 0, handlers: 0 } unless config&.dig(:events)

        stats = { events: 0, handlers: 0 }

        config[:events].each do |event_name, event_config|
          register_event_handlers(event_name, event_config, file_path)
          stats[:events] += 1
          stats[:handlers] += event_config[:handlers]&.size || 0
        end

        stats
      end

      private

      # Find all event_handlers.yml files
      def config_files
        files = []

        # Main app config
        main_config = Rails.root.join("config/event_handlers.yml")
        files << main_config if File.exist?(main_config)

        # Pack configs
        pack_configs = Dir.glob(Rails.root.join("packs/*/config/event_handlers.yml"))
        files.concat(pack_configs)

        files
      end

      # Register all handlers for a single event
      def register_event_handlers(event_name, event_config, file_path)
        event_class_name = event_config[:event_class]
        handlers_config = event_config[:handlers] || []

        return if handlers_config.empty?

        # Constantize event class
        begin
          event_class = event_class_name.constantize
        rescue NameError => e
          raise ConfigurationError, "Event class '#{event_class_name}' not found (from #{file_path}): #{e.message}"
        end

        # Register each handler
        handlers_config.each do |handler_config|
          register_single_handler(event_class, handler_config, file_path)
        end
      end

      # Register a single handler
      def register_single_handler(event_class, handler_config, file_path)
        handler_class_name = handler_config[:class]

        # Constantize handler class
        begin
          handler_class = handler_class_name.constantize
        rescue NameError => e
          raise ConfigurationError, "Handler class '#{handler_class_name}' not found (from #{file_path}): #{e.message}"
        end

        # Create handler instance
        handler = handler_class.new

        # Determine async setting (YAML explicit value takes precedence over default)
        async = if handler_config.key?(:async)
          handler_config[:async]
        else
          EventBus.configuration.default_async
        end

        # Get async_priority from YAML (default to :normal if not specified)
        async_priority = handler_config[:async_priority]&.to_sym || :normal

        # Register with EventBus
        EventBus.subscribe(
          event_class,
          handler,
          priority: handler_config[:priority] || 5,
          async: async,
          async_priority: async_priority,
          error_strategy: (handler_config[:error_strategy] || :log).to_sym,
        )
      end

      # Log loading statistics
      def log_loading_stats(stats)
        if stats[:files].zero?
          logger.info("EventBus-#{EventBus::VERSION} No YAML handler configs found")
          return
        end

        if stats[:errors].any?
          stats[:errors].each do |error_info|
            logger.error(
              "EventBus-#{EventBus::VERSION} Failed to load handlers from #{error_info[:file]}: #{error_info[:error]}",
            )
          end
        end

        logger.info(
          "EventBus-#{EventBus::VERSION} Loaded #{stats[:handlers]} handlers " \
          "for #{stats[:events]} events from #{stats[:files]} YAML files",
        )
      end

      def logger
        EventBus.configuration.logger
      end
    end
  end
end
