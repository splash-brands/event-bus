# frozen_string_literal: true

require_relative "lib/event_bus/version"

Gem::Specification.new do |spec|
  spec.name = "event_bus"
  spec.version = EventBus::VERSION
  spec.authors = ["Rafal Grabowski"]
  spec.email = ["rafal.grabowski@gmail.com"]

  spec.summary = "In-process event bus with middleware, transaction awareness, and async handlers"
  spec.description = "EventBus is a high-performance, synchronous event dispatcher for Ruby applications. "\
                     "Features middleware support, automatic transaction deferral, async handlers via ActiveJob, "\
                     "handler priorities, and flexible error handling strategies."
  spec.homepage = "https://github.com/splash-brands/event-bus"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/splash-brands/event-bus"
  spec.metadata["changelog_uri"] = "https://github.com/splash-brands/event-bus/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/splash-brands/event-bus/issues"
  spec.metadata["documentation_uri"] = "https://github.com/splash-brands/event-bus/blob/main/README.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies - Support Rails 7.0+ and Rails 8.0+
  spec.add_dependency "activerecord", ">= 7.0", "< 9.0"
  spec.add_dependency "activesupport", ">= 7.0", "< 9.0"

  # Actor system (concurrent processing)
  spec.add_dependency "concurrent-ruby", "~> 1.3"

  # Development dependencies
  spec.add_development_dependency "sqlite3", "~> 2.1"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "activejob", ">= 7.0", "< 9.0"
end
