# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeProvider
        class << self
          attr_accessor :last_path

          def new(path)
            self.last_path = path
            self
          end

          def load
            { "mammoth" => "config" }
          end
        end
      end

      class FakeApplication
        class << self
          attr_accessor :loaded_config, :started

          def new(config)
            self.loaded_config = config
            self
          end

          def start
            self.started = true
          end
        end
      end

      class EmbeddedMammothTest < Minitest::Test
        def setup
          FakeProvider.last_path = nil
          FakeApplication.loaded_config = nil
          FakeApplication.started = false
        end

        def test_start_uses_injected_application
          configuration = Configuration.new({ "mammoth" => { "config_path" => "/tmp/mammoth.yml" } }, env: {})
          embedded = EmbeddedMammoth.new(
            configuration,
            config_provider: FakeProvider,
            application_factory: ->(config) { FakeApplication.new(config) }
          )

          embedded.start

          assert_equal "/tmp/mammoth.yml", FakeProvider.last_path
          assert_equal({ "mammoth" => "config" }, FakeApplication.loaded_config)
          assert FakeApplication.started
        end

        def test_build_application_uses_config_provider_and_factory
          configuration = Configuration.new({ "mammoth" => { "config_path" => "/tmp/mammoth.yml" } }, env: {})
          built = nil
          embedded = EmbeddedMammoth.new(
            configuration,
            config_provider: FakeProvider,
            application_factory: lambda do |config|
              built = config
              FakeApplication.new(config)
            end
          )

          result = embedded.send(:build_application)

          assert_equal({ "mammoth" => "config" }, built)
          assert_equal FakeApplication, result
        end
      end
    end
  end
end
