# frozen_string_literal: true

namespace :eventbus do
  desc "Validate all pack events.yml configurations"
  task validate: :environment do
    puts "Validating EventBus pack configurations..."
    puts "=" * 80

    validator = EventBus::ConfigValidator.new(Rails.root)
    results = validator.validate_all

    if results.empty?
      puts "⚠️  No pack events.yml files found"
      puts "   Expected location: packs/<pack>/config/events.yml"
      exit 0
    end

    # Process results
    valid_count = 0
    error_count = 0
    warning_count = 0

    results.each do |result|
      puts "\nChecking #{result.pack_name} pack..."

      if result.valid?
        puts "  ✅ Configuration valid"
        valid_count += 1
      else
        error_count += result.errors.size
      end

      warning_count += result.warnings.size
    end

    # Print summary
    puts "\n" + ("=" * 80)
    puts "Validation Summary:"
    puts "  Valid configs: #{valid_count}"
    puts "  Errors: #{error_count}"
    puts "  Warnings: #{warning_count}"

    # Print errors
    results.each do |result|
      next if result.errors.empty?

      puts "\n❌ Errors in #{result.pack_name}:"
      result.errors.each { |e| puts "  - #{e}" }
    end

    # Print warnings
    results.each do |result|
      next if result.warnings.empty?

      puts "\n⚠️  Warnings in #{result.pack_name}:"
      result.warnings.each { |w| puts "  - #{w}" }
    end

    # Exit status
    if error_count > 0
      puts "\n💥 Validation FAILED - fix errors above"
      exit 1
    elsif warning_count > 0
      puts "\n⚠️  Validation passed with warnings"
      exit 0
    else
      puts "\n✅ All event configurations valid!"
      exit 0
    end
  end

  desc "List all configured events across packs"
  task list: :environment do
    puts "EventBus Configured Events"
    puts "=" * 80

    lister = EventBus::ConfigLister.new(Rails.root)
    summary = lister.list_all

    if summary.total_count.zero?
      puts "No pack events.yml files found"
      exit 0
    end

    # List events by pack
    summary.packs.each do |pack|
      puts "\n📦 #{pack.name.upcase} Pack"
      puts "-" * 80

      pack.events.each do |event|
        icon = event.persist_to_outbox? ? "💾" : "🔷"
        persistence = event.persist_to_outbox? ? "OutboxRelay" : "In-Process Only"

        puts "#{icon} #{event.name}"
        puts "   Persistence: #{persistence}"
        puts "   Description: #{event.first_line_description}"
        puts
      end
    end

    # Print summary
    puts "\n" + ("=" * 80)
    puts "Total events: #{summary.total_count}"
    puts "  Persisted (OutboxRelay): #{summary.persisted_count}"
    puts "  In-Process only: #{summary.internal_count}"
  end

  desc "Show EventBus middleware chain"
  task middleware: :environment do
    puts "EventBus Middleware Chain"
    puts "=" * 80
    puts

    if EventBus.middleware_chain.empty?
      puts "No middleware registered"
      exit 0
    end

    EventBus.middleware_chain.each_with_index do |middleware, index|
      puts "  #{index + 1}. #{middleware.class.name}"
    end

    puts
    puts "Total: #{EventBus.middleware_chain.size} middleware(s)"
  end

  desc "Show registered event handlers"
  task handlers: :environment do
    puts "Registered Event Handlers"
    puts "=" * 80
    puts

    subscriptions_by_event = EventBus.handlers

    if subscriptions_by_event.empty?
      puts "No event handlers registered"
      exit 0
    end

    total_handlers = 0

    subscriptions_by_event.each do |event_class, handlers|
      puts "\n#{event_class.name}:"
      puts "-" * 80

      handlers.sort_by { |h| -h.priority }.each do |handler|
        total_handlers += 1

        handler_name = if handler.handler.respond_to?(:class)
          handler.handler.class.name
        elsif handler.handler.is_a?(Proc)
          "Lambda/Proc"
        else
          handler.handler.to_s
        end

        puts "  • #{handler_name}"
        puts "    Priority: #{handler.priority}"
        puts "    Async: #{handler.async}"
        puts "    Error Strategy: #{handler.error_strategy}"
        puts
      end
    end

    puts "=" * 80
    puts "Total: #{total_handlers} handler(s) registered for #{subscriptions_by_event.size} event(s)"
  end

  desc "Generate events.yml template for a pack"
  task :generate, [:pack_name] => :environment do |_t, args|
    pack_name = args[:pack_name]

    if pack_name.nil? || pack_name.strip.empty?
      puts "❌ Error: Pack name required"
      puts "Usage: rake eventbus:generate[pack_name]"
      puts "Example: rake eventbus:generate[orders]"
      exit 1
    end

    path = Rails.root.join("packs", pack_name, "config", "events.yml")

    if File.exist?(path)
      puts "❌ Error: Configuration already exists at #{path}"
      puts "Remove existing file first or edit it directly"
      exit 1
    end

    template = <<~YAML
      # frozen_string_literal: true

      # EventBus Configuration - #{pack_name.camelize} Pack Events
      #
      # This file defines domain events for the #{pack_name} pack and controls
      # whether they should be persisted to OutboxRelay for cross-process delivery.
      #
      # Configuration:
      #   persist_to_outbox: true/false
      #     - true: Event is persisted to OutboxRelay for reliable cross-process delivery
      #     - false: Event stays in-process only (fast, no DB overhead)
      #   description: Required explanation of event purpose and persistence decision
      #
      # Decision Guide:
      #   Use persist_to_outbox: true when:
      #     - External systems need this event (analytics, external integrations)
      #     - Event affects multiple services/packs
      #     - Event ordering across processes is critical
      #     - Event must survive process restarts
      #
      #   Use persist_to_outbox: false when:
      #     - Event is purely internal to this pack
      #     - No cross-process communication needed
      #     - Event is transient/notification only
      #     - Performance is critical and event can be lost

      events:
        # Example event configuration:
        # created:
        #   persist_to_outbox: false
        #   description: >
        #     Resource creation events for internal tracking.
        #     This event is NOT persisted because it's consumed entirely
        #     within the Rails process for real-time notifications.
    YAML

    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, template)

    puts "✅ Created #{path}"
    puts
    puts "Next steps:"
    puts "  1. Edit the file to add your events"
    puts "  2. Run: rake eventbus:validate"
    puts "  3. Configure event handlers in packs/#{pack_name}/config/initializers/"
  end

  desc "Check EventBus configuration and status"
  task status: :environment do
    puts "EventBus Status"
    puts "=" * 80
    puts

    # Gem version
    puts "EventBus Version: #{EventBus::VERSION}"
    puts

    # Configuration
    config = EventBus.configuration
    puts "Configuration:"
    puts "  Max Handler Time: #{config.max_handler_time}s"
    puts "  Instrumentation: #{config.enable_instrumentation ? 'Enabled' : 'Disabled'}"
    puts "  Logger: #{config.logger.class.name}"
    puts

    # Middleware
    puts "Middleware Chain: #{EventBus.middleware_chain.size} middleware(s)"
    EventBus.middleware_chain.each_with_index do |middleware, index|
      puts "  #{index + 1}. #{middleware.class.name}"
    end
    puts

    # Packs with events.yml
    config_files = Dir.glob(Rails.root.join("packs", "*", "config", "events.yml"))
    puts "Configured Packs: #{config_files.size}"
    config_files.each do |file|
      pack_name = file.split(File::SEPARATOR)[-3]
      yaml = YAML.load_file(file)
      event_count = yaml["events"]&.size || 0
      puts "  • #{pack_name} (#{event_count} event(s))"
    rescue => e
      puts "  • #{pack_name} (error: #{e.message})"
    end
    puts

    # Registered handlers
    subscriptions = EventBus.handlers
    total_handlers = subscriptions.values.flatten.size
    puts "Registered Handlers: #{total_handlers} handler(s) for #{subscriptions.size} event(s)"
  end
end
