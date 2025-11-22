# frozen_string_literal: true

module EventBus
  # Lists EventBus pack configurations and events
  #
  # Provides summary information about configured events:
  # - Total event count
  # - Persistence breakdown (OutboxRelay vs in-process)
  # - Per-pack event details
  #
  # @example
  #   lister = EventBus::ConfigLister.new(Rails.root)
  #   summary = lister.list_all
  #   puts "Total events: #{summary.total_count}"
  #   puts "Persisted: #{summary.persisted_count}"
  class ConfigLister
    EventInfo = Struct.new(:name, :persist_to_outbox, :description, keyword_init: true) do
      def persist_to_outbox?
        persist_to_outbox == true
      end

      def first_line_description
        description&.strip&.lines&.first&.strip
      end
    end

    PackInfo = Struct.new(:name, :events, keyword_init: true) do
      def event_count
        events.size
      end

      def persisted_count
        events.count(&:persist_to_outbox?)
      end
    end

    EventSummary = Struct.new(:packs, :total_count, :persisted_count, :internal_count, keyword_init: true)

    attr_reader :rails_root

    def initialize(rails_root)
      @rails_root = rails_root
    end

    # List all configured events across packs
    #
    # @return [EventSummary] summary of all configured events
    def list_all
      packs = load_all_packs
      total = packs.sum(&:event_count)
      persisted = packs.sum(&:persisted_count)

      EventSummary.new(
        packs: packs,
        total_count: total,
        persisted_count: persisted,
        internal_count: total - persisted
      )
    end

    private

    def load_all_packs
      config_files.sort.map { |file| load_pack_config(file) }.compact
    end

    def config_files
      Dir.glob(File.join(rails_root, "packs", "*", "config", "events.yml"))
    end

    def load_pack_config(config_file)
      pack_name = extract_pack_name(config_file)

      begin
        yaml = YAML.load_file(config_file)
        return nil unless yaml["events"].is_a?(Hash)

        events = yaml["events"].map do |event_name, config|
          EventInfo.new(
            name: event_name,
            persist_to_outbox: config["persist_to_outbox"],
            description: config["description"]
          )
        end

        PackInfo.new(name: pack_name, events: events)
      rescue => e
        # Silently skip invalid configs (validation task will catch these)
        nil
      end
    end

    def extract_pack_name(file_path)
      file_path.split(File::SEPARATOR)[-3]
    end
  end
end
