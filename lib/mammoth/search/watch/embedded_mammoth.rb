# frozen_string_literal: true

require "mammoth"

module Mammoth
  module Search
    module Watch
      class EmbeddedMammoth
        attr_reader :configuration, :config_provider, :application_factory

        def initialize(
          configuration,
          config_provider: Mammoth::Configuration::Providers::FileProvider,
          application_factory: ->(mammoth_config) { Mammoth::Application.new(mammoth_config) }
        )
          @configuration = configuration
          @config_provider = config_provider
          @application_factory = application_factory
        end

        def start(application: nil)
          app = application || build_application
          app.start
        end

        private

        def build_application
          mammoth_config = config_provider.new(configuration.mammoth.config_path).load
          application_factory.call(mammoth_config)
        end
      end
    end
  end
end
