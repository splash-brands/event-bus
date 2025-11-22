# frozen_string_literal: true

module EventBus
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates EventBus initializer with default configuration"

      def copy_initializer
        template "config/initializers/event_bus.rb"
      end

      def show_readme
        readme "INSTALL" if behavior == :invoke
      end
    end
  end
end
