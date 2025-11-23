# frozen_string_literal: true

module EventBus
  # Validates EventBus pack configuration files (events.yml)
  #
  # Checks for:
  # - Valid YAML syntax
  # - Required fields (persist_to_outbox, description)
  # - Required 'reason' field for persisted events (persist_to_outbox: true)
  # - Correct data types (boolean for persist_to_outbox)
  # - Non-empty descriptions and reasons
  #
  # @example
  #   validator = EventBus::ConfigValidator.new(Rails.root)
  #   results = validator.validate_all
  #   results.each do |result|
  #     puts "#{result.pack_name}: #{result.valid? ? '✅' : '❌'}"
  #   end
  class ConfigValidator
    ValidationResult = Struct.new(:pack_name, :valid?, :errors, :warnings, keyword_init: true) do
      def initialize(pack_name:, valid:, errors: [], warnings: [])
        super(pack_name: pack_name, valid?: valid, errors: errors, warnings: warnings)
      end
    end

    attr_reader :rails_root

    def initialize(rails_root)
      @rails_root = rails_root
    end

    # Validate all pack event configurations
    #
    # @return [Array<ValidationResult>] validation results for each pack
    def validate_all
      config_files.map { |file| validate_pack_config(file) }
    end

    private

    def config_files
      Dir.glob(File.join(rails_root, "packs", "*", "config", "events.yml"))
    end

    def validate_pack_config(config_file)
      pack_name = extract_pack_name(config_file)
      errors = []
      warnings = []

      begin
        config = YAML.load_file(config_file)
        errors.concat(validate_structure(config, config_file))

        if config["events"].is_a?(Hash)
          result = validate_events(config["events"], config_file, pack_name)
          errors.concat(result[:errors])
          warnings.concat(result[:warnings])
        end
      rescue Psych::SyntaxError => e
        errors << "Invalid YAML syntax: #{e.message}"
      rescue => e
        errors << "Error loading file: #{e.message}"
      end

      ValidationResult.new(
        pack_name: pack_name,
        valid: errors.empty?,
        errors: errors,
        warnings: warnings
      )
    end

    def validate_structure(config, config_file)
      errors = []
      errors << "Missing 'events' root key" unless config.is_a?(Hash) && config.key?("events")
      errors << "'events' must be a Hash" unless config["events"].is_a?(Hash)
      errors
    end

    def validate_events(events, config_file, pack_name)
      errors = []
      warnings = []

      events.each do |event_name, event_config|
        # Required fields
        unless event_config.key?("persist_to_outbox")
          errors << "Event '#{event_name}': missing 'persist_to_outbox' field"
        end

        unless event_config.key?("description")
          errors << "Event '#{event_name}': missing 'description' field"
        end

        # Type validation
        unless [true, false].include?(event_config["persist_to_outbox"])
          errors << "Event '#{event_name}': 'persist_to_outbox' must be true or false"
        end

        # Description validation
        if event_config["description"].nil? || event_config["description"].to_s.strip.empty?
          errors << "Event '#{event_name}': 'description' must be a non-empty string"
        elsif event_config["description"].to_s.length < 20
          warnings << "Event '#{event_name}': has very short description (< 20 chars)"
        end

        # Version field validation (optional, but must be valid semver if present)
        if event_config.key?("version")
          if event_config["version"].nil? || event_config["version"].to_s.strip.empty?
            errors << "Event '#{event_name}': 'version' must be a non-empty string"
          elsif !valid_semver?(event_config["version"])
            errors << "Event '#{event_name}': 'version' must be valid semantic version (e.g., '1.0.0', '2.1.3')"
          end
        end

        # Reason field validation for persisted events
        if event_config["persist_to_outbox"] == true
          # Require reason field explaining WHY this event needs cross-process delivery
          unless event_config.key?("reason")
            errors << "Event '#{event_name}': missing 'reason' field (required when persist_to_outbox: true)"
          end

          if event_config["reason"].nil? || event_config["reason"].to_s.strip.empty?
            errors << "Event '#{event_name}': 'reason' must be a non-empty string explaining why this event needs cross-process delivery"
          elsif event_config["reason"].to_s.length < 30
            warnings << "Event '#{event_name}': 'reason' is very short (< 30 chars). Consider explaining dependencies or external systems."
          end
        end

        # OutboxRelay integration check (if available)
        next unless event_config["persist_to_outbox"] == true

        if defined?(OutboxRelay)
          topic = determine_topic(pack_name)
          outbox_partitions = OutboxRelay.configuration&.partitions || {}

          unless outbox_partitions.key?(topic)
            warnings << "Event '#{event_name}': configured to persist, but topic '#{topic}' not found in outbox_consumers.yml"
          end
        end
      end

      { errors: errors, warnings: warnings }
    end

    def determine_topic(pack_name)
      "#{pack_name}_updates"
    end

    def extract_pack_name(file_path)
      file_path.split(File::SEPARATOR)[-3]
    end

    def valid_semver?(version)
      # Semantic versioning format: MAJOR.MINOR.PATCH (e.g., 1.0.0, 2.3.1)
      version.to_s.match?(/\A\d+\.\d+\.\d+\z/)
    end
  end
end
