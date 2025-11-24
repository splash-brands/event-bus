# frozen_string_literal: true

require "yaml"

module EventBus
  # Loads pack event configurations from events.yml files.
  #
  # Determines which events should be persisted to outbox for cross-process delivery.
  # Each pack defines its event persistence strategy in packs/*/config/events.yml.
  #
  # YAML Structure:
  #   events:
  #     order_paid:
  #       persist_to_outbox: true
  #       description: "Order payment events must be delivered to external systems"
  #     order_validation_failed:
  #       persist_to_outbox: false
  #       description: "Internal validation errors, no cross-process delivery needed"
  #
  # @example Setup in Rails
  #   config_loader = EventBus::PackConfigLoader.new(Rails.root)
  #
  #   # Check if event should persist
  #   event = Orders::Events::OrderPaid.new(...)
  #   config_loader.should_persist?(event)  # => true
  #   config_loader.pack_name_for(event)    # => "orders"
  #
  class PackConfigLoader
    attr_reader :root_path, :configs

    # @param root_path [Pathname, String] Application root path (e.g., Rails.root)
    def initialize(root_path)
      @root_path = Pathname.new(root_path)
      @configs = load_all_configs
    end

    # Check if event should be persisted to outbox.
    #
    # Searches through all pack configs to find event configuration.
    # Returns false if event not found or persist_to_outbox is not explicitly true.
    #
    # @param event [Object] Event instance
    # @return [Boolean] true if event is configured to persist
    def should_persist?(event)
      event_config, _pack_name = find_event_config(event)
      event_config&.dig("persist_to_outbox") == true
    end

    # Find pack name for event.
    #
    # This handles cases where namespace doesn't match pack directory name.
    # Example: EmbNeedles namespace lives in embroidery pack
    #
    # @param event [Object] Event instance
    # @return [String, nil] Pack directory name (e.g., "embroidery", "orders")
    def pack_name_for(event)
      _event_config, pack_name = find_event_config(event)
      pack_name
    end

    # Find event configuration across all packs.
    #
    # Searches through all loaded pack configs to find this event.
    # This handles namespace mismatches (e.g., EmbNeedles in embroidery pack).
    #
    # @param event [Object] Event instance
    # @return [Array<Hash, String>, Array<nil, nil>] [event_config, pack_name] or [nil, nil]
    def find_event_config(event)
      event_name = event_name_from_class(event)

      configs.each do |pack_name, pack_config|
        event_config = pack_config.dig("events", event_name)
        return [event_config, pack_name] if event_config
      end

      [nil, nil]
    end

    # Reload all pack configurations from disk.
    #
    # Useful for development/testing when configs change.
    #
    # @return [Hash] Reloaded configurations
    def reload!
      @configs = load_all_configs
    end

    # Get all pack configurations.
    #
    # @return [Hash] Hash of pack_name => config
    def all_configs
      configs
    end

    private

    # Load all events.yml configurations from packs.
    #
    # Searches packs/*/config/events.yml and loads each one.
    #
    # @return [Hash] Hash of pack_name => parsed_yaml_config
    def load_all_configs
      loaded_configs = {}

      config_files.each do |file_path|
        pack_name = extract_pack_name(file_path)
        next unless pack_name

        begin
          yaml = YAML.load_file(file_path)
          loaded_configs[pack_name] = yaml if yaml.is_a?(Hash)
        rescue => e
          warn_loading_error(pack_name, file_path, e)
        end
      end

      loaded_configs
    end

    # Find all events.yml files in pack directories.
    #
    # @return [Array<String>] Array of absolute file paths
    def config_files
      Dir.glob(root_path.join("packs", "*", "config", "events.yml"))
    end

    # Extract pack directory name from file path.
    #
    # Example: "/app/packs/orders/config/events.yml" => "orders"
    #
    # @param file_path [String] Full path to events.yml
    # @return [String, nil] Pack directory name
    def extract_pack_name(file_path)
      parts = file_path.split("/")
      packs_index = parts.index("packs")
      return nil unless packs_index

      parts[packs_index + 1] # Next element after "packs" is pack name
    end

    # Extract event name from event class.
    #
    # Converts: Orders::Events::OrderPaid → order_paid
    #           EmbNeedles::Events::ThreadUpdated → thread_updated
    #
    # @param event [Object] Event instance
    # @return [String] Underscored event name
    def event_name_from_class(event)
      event.class.name.demodulize.underscore
    end

    # Log warning when config file fails to load.
    #
    # @param pack_name [String] Pack name
    # @param file_path [String] File path
    # @param error [Exception] Loading error
    def warn_loading_error(pack_name, file_path, error)
      if defined?(Rails) && Rails.logger
        Rails.logger.warn(
          "EventBus: Failed to load events.yml for pack '#{pack_name}' " \
          "from #{file_path}: #{error.message}",
        )
      else
        warn "EventBus: Failed to load events.yml for pack '#{pack_name}' " \
             "from #{file_path}: #{error.message}"
      end
    end
  end
end
