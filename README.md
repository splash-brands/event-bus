# EventBus

High-performance, synchronous event dispatcher for Ruby applications with middleware support, automatic transaction deferral, and async handlers.

## Features

- **🎯 Synchronous Event Dispatch** - Fast in-memory event handling for immediate side effects
- **🔌 Middleware Support** - Chain of responsibility pattern for cross-cutting concerns
- **🔄 Transaction Awareness** - Automatic deferral until ActiveRecord transaction commits
- **⚡ Async Handlers** - Background job execution via ActiveJob with priority queues
- **🚀 Async-first Mode** - Configurable default to async execution (reduces latency 50-100ms → 2-5ms)
- **📊 Priority Queues** - 4 Sidekiq queues (critical, high, normal, low) for async handlers
- **🔁 Retry Strategy** - Automatic retry with comprehensive observability
- **📈 Event Versioning** - VERSION field support for gradual schema evolution
- **📊 Observability** - Logging, instrumentation, and Sentry integration
- **🎨 Flexible Error Handling** - Per-handler error strategies (log, raise, retry, ignore)

## Installation

Add to your Gemfile:

```ruby
gem 'event_bus'
```

Then run:

```bash
$ bundle install
$ rails generate event_bus:install
```

This creates `config/initializers/event_bus.rb` with default configuration and examples.

Or install directly:

```bash
$ gem install event_bus
```

## Quick Start

### 1. Define Events

```ruby
class OrderPaid
  VERSION = "1.0.0"  # Semantic versioning for schema evolution

  attr_reader :order_id, :amount

  def initialize(order_id:, amount:)
    @order_id = order_id
    @amount = amount
  end

  # Required: event data for serialization
  def to_h
    {
      _version: VERSION,  # Include version in payload
      order_id: order_id,
      amount: amount
    }
  end

  # Required: partition key for event distribution
  def partition_key
    order_id
  end
end
```

### 2. Create Handlers

```ruby
class SendOrderConfirmationHandler
  def call(event)
    OrderMailer.confirmation(event.order_id).deliver_later
  end
end

class UpdateAnalyticsHandler
  def call(event)
    Analytics.track('order_paid', order_id: event.order_id, amount: event.amount)
  end
end
```

### 3. Subscribe Handlers

```ruby
# In Rails initializer (config/initializers/event_bus.rb)
EventBus.subscribe(OrderPaid, SendOrderConfirmationHandler.new, priority: 10)
EventBus.subscribe(OrderPaid, UpdateAnalyticsHandler.new, priority: 5)
```

### 4. Publish Events

```ruby
# Inside ActiveRecord transaction - automatically deferred until commit
ActiveRecord::Base.transaction do
  order.update!(status: :paid)
  EventBus.publish(OrderPaid.new(order_id: order.id, amount: order.total))
  # ↑ Handlers execute AFTER transaction commits
end
```

## Core Concepts

### Event Priority

Handlers execute in priority order (1-10, higher = earlier):

```ruby
EventBus.subscribe(OrderPaid, CriticalHandler.new, priority: 10)  # Executes first
EventBus.subscribe(OrderPaid, NormalHandler.new, priority: 5)     # Executes second
```

### Error Strategies

Configure per-handler error handling:

```ruby
# :log - Log error and continue (default)
EventBus.subscribe(OrderPaid, handler, error_strategy: :log)

# :raise - Stop execution and raise error
EventBus.subscribe(OrderPaid, handler, error_strategy: :raise)

# :retry - Retry up to 3 times with backoff (uses RetryHandlerJob)
EventBus.subscribe(OrderPaid, handler, error_strategy: :retry)

# :ignore - Silently ignore errors
EventBus.subscribe(OrderPaid, handler, error_strategy: :ignore)
```

### Async Handlers

Execute handlers in background jobs:

```ruby
# Async execution via ActiveJob
EventBus.subscribe(OrderPaid, SlowHandler.new, async: true)

# When event published:
# 1. Event serialized to hash
# 2. AsyncHandlerJob enqueued to Sidekiq/ActiveJob
# 3. Handler instantiated and executed in background worker
```

### Transaction Awareness

Events published inside transactions are automatically deferred:

```ruby
# Auto-defer (default behavior)
ActiveRecord::Base.transaction do
  order.update!(status: :paid)
  EventBus.publish(OrderPaid.new(...))  # Deferred until commit
end
# ↑ Handlers execute here after successful commit

# Force immediate execution
ActiveRecord::Base.transaction do
  EventBus.publish(OrderPaid.new(...), defer: false)  # Executes immediately
end

# Bypass deferral completely
EventBus.publish_now(OrderPaid.new(...))  # Always immediate
```

**Rollback Safety:**
```ruby
ActiveRecord::Base.transaction do
  order.update!(status: :paid)
  EventBus.publish(OrderPaid.new(...))
  raise ActiveRecord::Rollback  # Event NEVER executed
end
```

### Middleware

Add cross-cutting concerns with middleware:

```ruby
class LoggingMiddleware
  def call(event, next_middleware)
    Rails.logger.info("Publishing: #{event.class.name}")
    next_middleware.call(event)
    Rails.logger.info("Published: #{event.class.name}")
  end
end

class TimingMiddleware
  def call(event, next_middleware)
    start = Time.now
    next_middleware.call(event)
    duration = Time.now - start
    Rails.logger.info("Event #{event.class.name} took #{duration}s")
  end
end

EventBus.use(LoggingMiddleware.new)
EventBus.use(TimingMiddleware.new)
```

### Catch-All Handlers

Subscribe to all events:

```ruby
class AuditLogHandler
  def call(event)
    AuditLog.create!(
      event_type: event.class.name,
      event_data: event.to_h,
      timestamp: Time.current
    )
  end
end

EventBus.subscribe_all(AuditLogHandler.new)
```

### Event Versioning

Track event schema evolution with semantic versioning:

```ruby
class OrderPaid
  VERSION = "1.0.0"  # MAJOR.MINOR.PATCH format

  def to_h
    {
      _version: VERSION,
      order_id: order_id,
      amount: amount
    }
  end
end
```

**Version Evolution Example:**
```ruby
# v1.0.0 - Initial version
{ _version: "1.0.0", order_id: 123, amount: 99.99 }

# v1.1.0 - Add optional field (backward compatible)
{ _version: "1.1.0", order_id: 123, amount: 99.99, currency: "USD" }

# v2.0.0 - Breaking change (rename field)
{ _version: "2.0.0", order_id: 123, total_amount: 99.99, currency: "USD" }
```

**Handler Version Support:**
```ruby
class OrderPaidHandler
  def call(event)
    case event._version
    when "1.0.0"
      process_v1(event)
    when "1.1.0", "1.2.0"
      process_v1_x(event)  # Handle minor versions together
    when /^2\./
      process_v2(event)  # Handle all v2.x versions
    else
      raise "Unsupported event version: #{event._version}"
    end
  end

  private

  def process_v1(event)
    # Handle v1.0.0 format
    amount = event.amount
    currency = "USD"  # Default for v1
  end

  def process_v2(event)
    # Handle v2.x format
    amount = event.total_amount  # Field renamed
    currency = event.currency
  end
end
```

**Benefits:**
- **Gradual Migration**: Deploy new event versions without breaking existing handlers
- **Backward Compatibility**: Handlers can support multiple versions simultaneously
- **Clear Evolution**: Track schema changes over time
- **Safe Deployments**: Version mismatches are detected early

## Background Jobs

### AsyncHandlerJob

For non-blocking handler execution:

```ruby
# Subscribe with async: true
EventBus.subscribe(OrderPaid, ExternalApiHandler.new, async: true)

# What happens:
# 1. Event serialized: event.to_h
# 2. Job enqueued: AsyncHandlerJob.perform_later(handler_class, event_data)
# 3. Handler instantiated in worker: handler = ExternalApiHandler.new
# 4. Event rebuilt: event = OpenStruct.new(event_data)
# 5. Handler called: handler.call(event)
```

### RetryHandlerJob

For fault-tolerant handler execution with comprehensive observability:

```ruby
# Subscribe with retry strategy
EventBus.subscribe(OrderPaid, FlakeyApiHandler.new, error_strategy: :retry)

# What happens on failure:
# Attempt 1: Immediate retry
# Attempt 2: Wait 5 seconds, retry
# Attempt 3: Wait 5 seconds, retry (final attempt)
# All failed: Sentry alert + Datadog error log + Sidekiq dead set
```

**4-Layer Observability Stack:**

1. **Sentry Alerts** - Immediate notifications when retries exhausted
   ```ruby
   Sentry.capture_exception(error,
     tags: { handler: "FlakeyApiHandler", job_class: "RetryHandlerJob" },
     extra: { event_payload: {...}, original_error: "...", attempts: 3 },
     fingerprint: ["retry_handler_job", "FlakeyApiHandler", "StandardError"]
   )
   ```

2. **Enhanced Logging** - Full error context with backtrace
   ```ruby
   logger.error(
     event: "retry_handler_job.retries_exhausted",
     handler: "FlakeyApiHandler",
     event_payload: {...},
     original_error: "Connection timeout",
     final_error: "Still failing after 3 attempts",
     backtrace: [...],
     job_id: "abc123",
     attempts: 3
   )
   ```

3. **ActiveSupport::Notifications** - APM metrics
   ```ruby
   ActiveSupport::Notifications.instrument("retry_handler_job.execute",
     handler: "FlakeyApiHandler",
     attempt: 2
   )
   ```

4. **Sidekiq UI** - Manual inspection of dead set (last resort)

## Async-first Mode

Dramatically reduce request latency by executing handlers in background jobs by default.

### Configuration

```ruby
# config/initializers/event_bus.rb
EventBus.configure do |config|
  # Enable async-first mode (default: false)
  config.default_async = true

  # Base queue name for async handlers
  config.async_queue = :eventbus_handlers

  # Priority-to-numeric mapping for handler execution order
  config.async_priorities = {
    critical: 10,  # Email alerts, critical notifications
    high: 8,       # Operator notifications, urgent updates
    normal: 5,     # Cache updates, logging, analytics
    low: 3,        # Reports, background analytics
  }
end
```

### Sidekiq Queue Setup

Add EventBus priority queues to your `config/sidekiq.yml`:

```yaml
:queues:
  - asap
  - eventbus_handlers_critical  # Process before standard queues
  - eventbus_handlers_high
  - default
  - eventbus_handlers_normal    # Process after standard queues
  - eventbus_handlers_low
```

### Handler Priority Configuration

```ruby
# Explicit async with priority (recommended)
EventBus.subscribe(
  OrderPaid,
  EmailNotificationHandler.new,
  async: true,
  async_priority: :critical,  # Routes to eventbus_handlers_critical queue
  priority: 10
)

# With default_async = true, handlers are async by default
EventBus.subscribe(
  OrderPaid,
  CacheUpdateHandler.new,
  async_priority: :normal,  # Routes to eventbus_handlers_normal queue
  priority: 5
)

# Force synchronous execution even with default_async = true
EventBus.subscribe(
  OrderPaid,
  TransactionCriticalHandler.new,
  async: false,  # Explicit sync
  priority: 10
)
```

### Performance Impact

**Before (Synchronous):**
```
Request latency: 50-100ms added per request
Blocking: Yes (handlers run in request thread)
Scalability: Limited by request thread pool
```

**After (Async-first):**
```
Request latency: 2-5ms added per request (95% reduction!)
Blocking: No (handlers run in background workers)
Scalability: Horizontal (add more Sidekiq workers)
Trade-off: Side-effects delayed by 100-500ms
```

### When to Use Sync vs Async

**Use Synchronous (async: false):**
- Transaction-critical operations (must succeed/fail with transaction)
- Immediate feedback required (e.g., validation errors)
- Order-dependent operations within same request
- Very fast handlers (<5ms)

**Use Asynchronous (async: true):**
- External API calls (Stripe, SendGrid, etc.)
- Email/notification sending
- Cache updates (can tolerate slight delay)
- Analytics/logging (non-critical)
- Slow operations (>50ms)

### Migration Strategy

**Phase 1: Infrastructure Setup** (No behavior change)
```ruby
# Keep default_async = false
EventBus.configure do |config|
  config.default_async = false
  config.async_queue = :eventbus_handlers
end

# Pre-configure all handlers with async_priority
EventBus.subscribe(handler, async: false, async_priority: :normal)
```

**Phase 2: Gradual Migration** (Enable per-handler)
```ruby
# Start with slow/non-critical handlers
EventBus.subscribe(
  OrderPaid,
  SendEmailHandler.new,
  async: true,              # Enable async explicitly
  async_priority: :high
)
```

**Phase 3: Async-first** (Flip default, opt-out sync)
```ruby
# Enable async by default
EventBus.configure do |config|
  config.default_async = true
end

# Opt-out for critical handlers
EventBus.subscribe(
  OrderPaid,
  CriticalHandler.new,
  async: false  # Explicit sync
)
```

### Monitoring

Track async handler performance:

```ruby
# In your APM (Datadog, New Relic, etc.)
ActiveSupport::Notifications.subscribe("async_handler_job.execute") do |name, start, finish, id, payload|
  duration = finish - start
  StatsD.timing("eventbus.async_handler", duration, tags: [
    "handler:#{payload[:handler]}",
    "queue:#{payload[:queue]}",
  ])
end
```

## Configuration

```ruby
# config/initializers/event_bus.rb
EventBus.configure do |config|
  # Logging
  config.logger = Rails.logger

  # Instrumentation (for APM like Datadog, New Relic)
  config.enable_instrumentation = true

  # Handler timeout (seconds)
  config.max_handler_time = 30

  # Async-first mode (default: false for backward compatibility)
  config.default_async = false

  # Base Sidekiq queue name for async handlers
  config.async_queue = :eventbus_handlers

  # Priority-to-numeric mapping for queue routing
  config.async_priorities = {
    critical: 10,  # Highest priority (email alerts, critical notifications)
    high: 8,       # High priority (operator notifications, urgent updates)
    normal: 5,     # Normal priority (cache updates, logging, analytics)
    low: 3,        # Low priority (reports, background analytics)
  }
end
```

**Configuration Options:**

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `logger` | Logger | `Rails.logger` | Logger instance for EventBus |
| `enable_instrumentation` | Boolean | `true` | Enable ActiveSupport::Notifications |
| `max_handler_time` | Integer | `30` | Handler timeout in seconds |
| `default_async` | Boolean | `false` | Execute handlers async by default |
| `async_queue` | Symbol | `:eventbus_handlers` | Base Sidekiq queue name |
| `async_priorities` | Hash | See above | Priority-to-numeric mapping |

## Testing

### RSpec Setup

```ruby
# spec/spec_helper.rb
require "active_job"
require "event_bus"

RSpec.configure do |config|
  config.before do
    EventBus.clear!  # Clear subscriptions between tests
  end
end
```

### Testing Handlers

```ruby
RSpec.describe SendOrderConfirmationHandler do
  let(:handler) { described_class.new }
  let(:event) { OrderPaid.new(order_id: 123, amount: 99.99) }

  it "sends confirmation email" do
    expect {
      handler.call(event)
    }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
  end
end
```

### Testing Event Publishing

```ruby
RSpec.describe Order do
  let(:order) { create(:order) }

  it "publishes OrderPaid event when marked as paid" do
    handler = instance_double("OrderPaidHandler", call: nil)
    EventBus.subscribe(OrderPaid, handler)

    order.mark_as_paid!

    expect(handler).to have_received(:call).with(
      have_attributes(order_id: order.id)
    )
  end
end
```

### Testing Transaction Deferral

```ruby
RSpec.describe "transaction awareness" do
  it "defers handler execution until commit" do
    handler = double("Handler", call: nil)
    EventBus.subscribe(OrderPaid, handler)

    ActiveRecord::Base.transaction do
      EventBus.publish(OrderPaid.new(order_id: 123, amount: 99.99))
      expect(handler).not_to have_received(:call)  # Not called yet
    end

    expect(handler).to have_received(:call)  # Called after commit
  end
end
```

## API Reference

### EventBus

#### `.subscribe(event_class, handler, priority: 5, async: false, async_priority: :normal, error_strategy: :log)`
Subscribe handler to event class.

**Parameters:**
- `event_class` - Event class to subscribe to
- `handler` - Handler instance (must respond to `call(event)`)
- `priority` - Execution order (1-10, higher = earlier)
- `async` - Execute in background job (default: `config.default_async`)
- `async_priority` - Sidekiq queue priority: `:critical`, `:high`, `:normal`, `:low` (default: `:normal`)
- `error_strategy` - Error handling: `:log`, `:raise`, `:retry`, `:ignore`

**Examples:**
```ruby
# Synchronous handler with high execution priority
EventBus.subscribe(OrderPaid, handler, priority: 10, async: false)

# Async handler with critical Sidekiq priority
EventBus.subscribe(OrderPaid, handler, async: true, async_priority: :critical)

# With default_async = true, specify sync explicitly
EventBus.subscribe(OrderPaid, handler, async: false, priority: 10)
```

#### `.subscribe_all(handler, priority: 5, async: false, async_priority: :normal, error_strategy: :log)`
Subscribe handler to all events (catch-all).

**Parameters:** Same as `.subscribe()` but without `event_class`.

#### `.publish(event, defer: :auto)`
Publish event to subscribed handlers.

**Parameters:**
- `event` - Event instance (must respond to `to_h` and `partition_key`)
- `defer` - Transaction deferral: `:auto` (default), `true`, `false`

#### `.publish_now(event)`
Publish immediately, bypassing transaction deferral.

#### `.use(middleware)`
Register middleware for cross-cutting concerns.

**Middleware contract:**
```ruby
def call(event, next_middleware)
  # before logic
  next_middleware.call(event)
  # after logic
end
```

#### `.clear!`
Clear all subscriptions and middleware (for testing).

#### `.in_transaction?`
Check if currently inside ActiveRecord transaction.

#### `.subscribers_for(event_class)`
Get all handlers subscribed to event class (for introspection).

## Performance

- **Synchronous Dispatch**: <1ms per event with 10 handlers
- **Async Handlers**: Non-blocking, executes in background workers
- **Transaction Deferral**: Minimal overhead (~0.5ms per event)
- **Async-first Mode**: Reduces request latency from 50-100ms to 2-5ms (95% reduction)

**Benchmark Results (10 handlers, production environment):**

| Mode | Request Latency | Throughput | Handler Execution | Side-effect Delay |
|------|----------------|------------|-------------------|-------------------|
| Synchronous | +50-100ms | 100 req/s | Immediate | 0ms |
| Async-first | +2-5ms | 1000+ req/s | Background | 100-500ms |

**Trade-offs:**
- **Sync**: Immediate execution, blocking, lower throughput
- **Async**: Delayed execution, non-blocking, higher throughput
- **Recommendation**: Use async-first for production, sync for development/testing

## Requirements

- Ruby >= 3.1.0
- ActiveRecord >= 7.0
- ActiveSupport >= 7.0
- ActiveJob >= 7.0 (for background jobs)
- concurrent-ruby ~> 1.3

## Integration with OutboxRelay

EventBus provides built-in middleware for integrating with OutboxRelay (transactional outbox pattern) for reliable cross-process event delivery.

### Architecture

The integration uses the **Adapter Pattern** with **Dependency Injection**:

- **EventBus::Middlewares::OutboxPersistence** - Main middleware (provided by gem)
- **EventBus::Adapters::BaseAdapter** - Abstract interface for persistence backends
- **EventBus::Adapters::OutboxRelayAdapter** - Concrete implementation for OutboxRelay gem
- **EventBus::PackConfigLoader** - Loads `events.yml` configurations from packs

### Setup

**1. Create events.yml in each pack**

Define which events should persist to outbox:

```yaml
# packs/orders/config/events.yml
events:
  order_paid:
    persist_to_outbox: true
    description: "Order payment events must be delivered to external systems"

  order_validation_failed:
    persist_to_outbox: false
    description: "Internal validation errors, no cross-process delivery needed"
```

**2. Configure middleware in Rails initializer**

```ruby
# config/initializers/event_bus.rb

# Create adapter (wraps OutboxPublisher from OutboxRelay gem)
adapter = EventBus::Adapters::OutboxRelayAdapter.new(OutboxPublisher)

# Create config loader (reads events.yml from all packs)
config_loader = EventBus::PackConfigLoader.new(Rails.root)

# Register middleware with dependency injection
EventBus.use(
  EventBus::Middlewares::OutboxPersistence.new(
    adapter: adapter,
    config_loader: config_loader,
    logger: Rails.logger
  )
)
```

### Custom Adapters

Implement custom adapters for other backends (Kafka, SQS, RabbitMQ):

```ruby
class MyKafkaAdapter < EventBus::Adapters::BaseAdapter
  def initialize(kafka_producer)
    @producer = kafka_producer
  end

  def publish(topic:, payload:, headers:)
    @producer.produce(
      payload.to_json,
      topic: topic,
      headers: headers
    )
  end
end

# Use custom adapter
adapter = MyKafkaAdapter.new(Kafka.producer)
EventBus.use(
  EventBus::Middlewares::OutboxPersistence.new(
    adapter: adapter,
    config_loader: config_loader
  )
)
```

### How It Works

1. **Event published** via `EventBus.publish(event)`
2. **Middleware executes**:
   - Runs all in-process handlers first (synchronous)
   - Checks `events.yml` via `PackConfigLoader`
   - If `persist_to_outbox: true`, calls adapter
3. **Adapter persists** to backend (OutboxRelay, Kafka, etc.)
4. **Background workers** asynchronously publish to message broker

### Benefits

- **Reusable** - Provided by gem, no code duplication
- **Testable** - Mock adapters via dependency injection
- **Flexible** - Supports multiple backends via adapter pattern
- **Zero coupling** - EventBus doesn't know about OutboxRelay/Kafka specifics
- **Safe** - Logs errors but doesn't fail request if outbox persistence fails

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests (`bundle exec rspec`)
4. Commit changes (`git commit -m 'Add amazing feature'`)
5. Push to branch (`git push origin feature/amazing-feature`)
6. Open Pull Request

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Credits

Built with ❤️ by [Rafal Grabowski](https://github.com/rafalgrabowski)

Inspired by event-driven architectures and domain-driven design principles.
