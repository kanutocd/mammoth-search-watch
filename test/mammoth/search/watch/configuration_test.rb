# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Mammoth
  module Search
    module Watch
      class ConfigurationTest < Minitest::Test
        def test_loads_defaults_and_env_fallbacks
          Dir.mktmpdir do |dir|
            path = File.join(dir, "search_watch.yml")
            File.write(path, <<~YAML)
              webhook:
                port: 9333
              database:
                url_env: DATABASE_URL
            YAML

            env = {
              "SEARCH_WATCH_CONFIG" => path,
              "DATABASE_URL" => "postgres://example",
              "SEARCH_WATCH_DEFAULT_TENANT_ID" => "tenant_global"
            }

            configuration = Configuration.load(nil, env:)

            assert configuration.embedded?
            refute configuration.sink_only?
            assert_equal 9333, configuration.webhook.port
            assert_equal "DATABASE_URL", configuration.database.url_env
            assert_equal "postgres://example", configuration.database_url
            assert_equal "tenant_global", configuration.global_tenant_id
            assert_equal "embedded", configuration.runtime.mode
            assert_equal "tenant_global", configuration.to_h.dig("tenancy", "default_tenant_id")
          end
        end

        def test_sink_mode_and_explicit_values_are_respected
          configuration = Configuration.new(
            {
              "runtime" => { "mode" => "sink" },
              "tenancy" => { "enabled" => false, "default_tenant_id" => "tenant_a" },
              "mammoth" => { "embedded" => false, "config_path" => "/tmp/mammoth.yml" }
            },
            env: { "DATABASE_URL" => "postgres://example" }
          )

          refute configuration.embedded?
          assert configuration.sink_only?
          refute configuration.tenancy.enabled
          refute configuration.mammoth.embedded
          assert_equal "/tmp/mammoth.yml", configuration.mammoth.config_path
        end

        def test_invalid_integer_raises_configuration_error
          error = assert_raises(ConfigurationError) do
            Configuration.new(
              {
                "webhook" => { "port" => "not-an-integer" }
              },
              env: {}
            )
          end

          assert_match("webhook.port", error.message)
        end

        def test_explicit_boolean_strings_are_parsed
          configuration = Configuration.new(
            {
              "tenancy" => { "enabled" => "false" },
              "mammoth" => { "embedded" => "true" },
              "lifecycle" => { "bootstrap_on_start" => "false" },
              "retention" => {
                "activities" => { "enabled" => true, "ttl" => "2h" },
                "observations" => { "enabled" => false },
                "drifts" => { "enabled" => true, "ttl" => 1800 },
                "scheduler" => { "interval_seconds" => "300" }
              }
            },
            env: {}
          )

          refute configuration.tenancy.enabled
          assert configuration.mammoth.embedded
          refute configuration.lifecycle.bootstrap_on_start
          assert_equal 7_200, configuration.retention.activities.ttl_seconds
          refute configuration.retention.observations.enabled
          assert_equal 1_800, configuration.retention.drifts.ttl_seconds
          assert_equal 300, configuration.retention.scheduler.interval_seconds
        end
      end
    end
  end
end
