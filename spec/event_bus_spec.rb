# frozen_string_literal: true

RSpec.describe EventBus do
  # Test event class
  class TestEvent
    attr_reader :data, :key

    def initialize(data:, key: "default")
      @data = data
      @key = key
    end

    def to_h
      { data: data, key: key }
    end

    def partition_key
      key
    end
  end

  # Test handler
  class TestHandler
    attr_reader :received_events

    def initialize
      @received_events = []
    end

    def call(event)
      @received_events << event
    end
  end

  before do
    EventBus.clear!
  end

  describe "VERSION" do
    it "has a version number" do
      expect(EventBus::VERSION).not_to be nil
    end
  end

  describe ".configure" do
    it "yields configuration object" do
      EventBus.configure do |config|
        expect(config).to be_a(EventBus::Configuration)
      end
    end

    it "allows setting configuration options" do
      EventBus.configure do |config|
        config.log_level = :info
        config.persist_to_outbox = false
        config.max_handler_time = 10
      end

      expect(EventBus.configuration.log_level).to eq(:info)
      expect(EventBus.configuration.persist_to_outbox).to be false
      expect(EventBus.configuration.max_handler_time).to eq(10)
    end
  end

  describe ".subscribe" do
    it "registers handler for event class" do
      handler = TestHandler.new
      EventBus.subscribe(TestEvent, handler)

      expect(EventBus.subscribers_for(TestEvent)).to include(handler)
    end

    it "registers handler with priority" do
      handler1 = TestHandler.new
      handler2 = TestHandler.new

      EventBus.subscribe(TestEvent, handler1, priority: 10)
      EventBus.subscribe(TestEvent, handler2, priority: 5)

      # Higher priority handlers should be first
      expect(EventBus.handlers[TestEvent].first.handler).to eq(handler1)
      expect(EventBus.handlers[TestEvent].last.handler).to eq(handler2)
    end

    it "raises error for invalid priority" do
      handler = TestHandler.new
      expect {
        EventBus.subscribe(TestEvent, handler, priority: 11)
      }.to raise_error(ArgumentError, /Priority must be 1-10/)
    end

    it "raises error for invalid error_strategy" do
      handler = TestHandler.new
      expect {
        EventBus.subscribe(TestEvent, handler, error_strategy: :invalid)
      }.to raise_error(ArgumentError, /Invalid error_strategy/)
    end
  end

  describe ".subscribe_all" do
    it "registers catch-all handler" do
      handler = TestHandler.new
      EventBus.subscribe_all(handler)

      expect(EventBus.catch_all).not_to be_empty
      expect(EventBus.catch_all.first.handler).to eq(handler)
    end
  end

  describe ".publish" do
    it "publishes event to subscribed handlers" do
      handler = TestHandler.new
      EventBus.subscribe(TestEvent, handler)

      event = TestEvent.new(data: "test")
      EventBus.publish(event, defer: false)

      expect(handler.received_events).to include(event)
    end

    it "publishes to multiple handlers in priority order" do
      received_order = []

      handler1 = Class.new do
        define_method(:call) { |_e| received_order << :handler1 }
      end.new

      handler2 = Class.new do
        define_method(:call) { |_e| received_order << :handler2 }
      end.new

      EventBus.subscribe(TestEvent, handler1, priority: 10)
      EventBus.subscribe(TestEvent, handler2, priority: 5)

      EventBus.publish(TestEvent.new(data: "test"), defer: false)

      expect(received_order).to eq([:handler1, :handler2])
    end

    it "publishes to catch-all handlers" do
      handler = TestHandler.new
      EventBus.subscribe_all(handler)

      event = TestEvent.new(data: "test")
      EventBus.publish(event, defer: false)

      expect(handler.received_events).to include(event)
    end

    it "raises error for invalid event" do
      invalid_event = Object.new

      expect {
        EventBus.publish(invalid_event, defer: false)
      }.to raise_error(ArgumentError, /Event must respond to #to_h/)
    end
  end

  describe ".use (middleware)" do
    it "registers middleware" do
      middleware = EventBus::LoggingMiddleware.new
      EventBus.use(middleware)

      expect(EventBus.middleware).to include(middleware)
    end

    it "executes middleware before handlers" do
      execution_order = []

      middleware = Class.new(EventBus::Middleware) do
        define_method(:call) do |event, next_middleware|
          execution_order << :middleware
          next_middleware.call(event)
        end
      end.new

      handler = Class.new do
        define_method(:call) { |_e| execution_order << :handler }
      end.new

      EventBus.use(middleware)
      EventBus.subscribe(TestEvent, handler)

      EventBus.publish(TestEvent.new(data: "test"), defer: false)

      expect(execution_order).to eq([:middleware, :handler])
    end

    it "raises error for invalid middleware" do
      invalid_middleware = Object.new

      expect {
        EventBus.use(invalid_middleware)
      }.to raise_error(ArgumentError, /Middleware must respond to #call/)
    end
  end

  describe ".clear!" do
    it "clears all subscriptions and middleware" do
      handler = TestHandler.new
      middleware = EventBus::LoggingMiddleware.new

      EventBus.subscribe(TestEvent, handler)
      EventBus.use(middleware)

      EventBus.clear!

      expect(EventBus.handlers).to be_empty
      expect(EventBus.catch_all).to be_empty
      expect(EventBus.middleware).to be_empty
    end
  end

  describe "error handling" do
    context "with :log strategy" do
      it "logs error and continues" do
        failing_handler = Class.new do
          define_method(:call) { |_e| raise "Handler failed" }
        end.new

        EventBus.subscribe(TestEvent, failing_handler, error_strategy: :log)

        expect {
          EventBus.publish(TestEvent.new(data: "test"), defer: false)
        }.not_to raise_error
      end
    end

    context "with :raise strategy" do
      it "raises PublishError" do
        failing_handler = Class.new do
          define_method(:call) { |_e| raise "Handler failed" }
        end.new

        EventBus.subscribe(TestEvent, failing_handler, error_strategy: :raise)

        expect {
          EventBus.publish(TestEvent.new(data: "test"), defer: false)
        }.to raise_error(EventBus::PublishError, /Handler .* failed/)
      end
    end

    context "with :ignore strategy" do
      it "silently ignores error" do
        failing_handler = Class.new do
          define_method(:call) { |_e| raise "Handler failed" }
        end.new

        EventBus.subscribe(TestEvent, failing_handler, error_strategy: :ignore)

        expect {
          EventBus.publish(TestEvent.new(data: "test"), defer: false)
        }.not_to raise_error
      end
    end
  end
end
