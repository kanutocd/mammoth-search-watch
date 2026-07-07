# frozen_string_literal: true

require "yaml"

module Mammoth
  module Search
    module Watch
      class Configuration
        DEFAULT_PATH = "config/search_watch.yml"
        DEFAULT_WEBHOOK_PATH = "/webhooks/mammoth/search-watch"
        DEFAULT_WEBHOOK_HOST = "0.0.0.0"
        DEFAULT_WEBHOOK_PORT = 9292
        DEFAULT_WEBHOOK_THREADS = 4
        DEFAULT_DATABASE_ROLE = "mammoth_search_watch"
        DEFAULT_TENANT_HEADER = "x-mammoth-tenant-id"
        DEFAULT_RUNTIME_MODE = "embedded"
        DEFAULT_BOOTSTRAP_ON_START = true

        Runtime = Struct.new(:mode, keyword_init: true) do
          def embedded?
            mode == "embedded"
          end

          def sink?
            mode == "sink"
          end
        end

        Webhook = Struct.new(:server, :host, :port, :path, :threads, :max_body_bytes, :root, keyword_init: true)
        Database = Struct.new(:url_env, :role, keyword_init: true)
        Tenancy = Struct.new(:enabled, :tenant_header, :default_tenant_id, keyword_init: true)
        MammothConfig = Struct.new(:embedded, :config_path, keyword_init: true)
        RetentionPolicy = Struct.new(:enabled, :ttl_seconds, keyword_init: true) do
          def enabled?
            enabled
          end
        end
        RetentionSchedulerConfig = Struct.new(:interval_seconds, keyword_init: true)
        Retention = Struct.new(:activities, :observations, :drifts, :scheduler, keyword_init: true)
        Lifecycle = Struct.new(:bootstrap_on_start, keyword_init: true) do
          def bootstrap_on_start?
            bootstrap_on_start
          end
        end

        attr_reader :runtime, :webhook, :database, :tenancy, :mammoth, :retention, :lifecycle, :source_path

        class << self
          def load(path = nil, env: ENV)
            path ||= env.fetch("SEARCH_WATCH_CONFIG", DEFAULT_PATH)
            new(YAML.safe_load(File.read(path), permitted_classes: [Symbol], aliases: true) || {}, env:, source_path: path)
          end
        end

        def initialize(raw = {}, env: ENV, source_path: nil)
          @env = env
          @source_path = source_path
          @raw = stringify_keys(raw || {})
          build!
        end

        def embedded?
          runtime.embedded?
        end

        def sink_only?
          runtime.sink?
        end

        def database_url
          env.fetch(database.url_env) do
            raise ConfigurationError, "missing database url environment variable #{database.url_env}"
          end
        end

        def global_tenant_id
          tenancy.default_tenant_id
        end

        def to_h
          {
            "runtime" => { "mode" => runtime.mode },
            "webhook" => {
              "server" => webhook.server,
              "host" => webhook.host,
              "port" => webhook.port,
              "path" => webhook.path,
              "threads" => webhook.threads,
              "max_body_bytes" => webhook.max_body_bytes,
              "root" => webhook.root
            },
            "database" => {
              "url_env" => database.url_env,
              "role" => database.role
            },
            "tenancy" => {
              "enabled" => tenancy.enabled,
              "tenant_header" => tenancy.tenant_header,
              "default_tenant_id" => tenancy.default_tenant_id
            },
            "retention" => {
              "activities" => retention_hash(retention.activities),
              "observations" => retention_hash(retention.observations),
              "drifts" => retention_hash(retention.drifts),
              "scheduler" => {
                "interval_seconds" => retention.scheduler.interval_seconds
              }
            },
            "lifecycle" => {
              "bootstrap_on_start" => lifecycle.bootstrap_on_start
            },
            "mammoth" => {
              "embedded" => mammoth.embedded,
              "config_path" => mammoth.config_path
            }
          }
        end

        private

        attr_reader :env

        def build!
          @runtime = Runtime.new(mode: fetch_string(%w[runtime mode], default: DEFAULT_RUNTIME_MODE))
          @webhook = Webhook.new(
            server: fetch_string(%w[webhook server], default: "agoo"),
            host: fetch_string(%w[webhook host], default: DEFAULT_WEBHOOK_HOST),
            port: fetch_integer(%w[webhook port], default: DEFAULT_WEBHOOK_PORT),
            path: fetch_string(%w[webhook path], default: DEFAULT_WEBHOOK_PATH),
            threads: fetch_integer(%w[webhook threads], default: DEFAULT_WEBHOOK_THREADS),
            max_body_bytes: fetch_integer(%w[webhook max_body_bytes], default: 1_048_576),
            root: fetch_string(%w[webhook root], default: Dir.pwd)
          )
          @database = Database.new(
            url_env: fetch_string(%w[database url_env], default: "DATABASE_URL"),
            role: fetch_string(%w[database role], default: DEFAULT_DATABASE_ROLE)
          )
          @tenancy = Tenancy.new(
            enabled: fetch_boolean(%w[tenancy enabled], default: true),
            tenant_header: fetch_string(%w[tenancy tenant_header], default: DEFAULT_TENANT_HEADER),
            default_tenant_id: resolve_default_tenant_id
          )
          @retention = Retention.new(
            activities: retention_policy(%w[retention activities], enabled_default: true, ttl_default: "24h"),
            observations: retention_policy(%w[retention observations], enabled_default: false, ttl_default: nil),
            drifts: retention_policy(%w[retention drifts], enabled_default: false, ttl_default: nil),
            scheduler: RetentionSchedulerConfig.new(
              interval_seconds: fetch_integer(%w[retention scheduler interval_seconds], default: 86_400)
            )
          )
          @lifecycle = Lifecycle.new(
            bootstrap_on_start: fetch_boolean(
              %w[lifecycle bootstrap_on_start],
              default: DEFAULT_BOOTSTRAP_ON_START
            )
          )
          @mammoth = MammothConfig.new(
            embedded: fetch_boolean(%w[mammoth embedded], default: runtime.embedded?),
            config_path: fetch_string(%w[mammoth config_path], default: "config/mammoth.yml")
          )
        end

        def resolve_default_tenant_id
          configured = @raw.dig("tenancy", "default_tenant_id")
          return configured unless blank?(configured)

          env["SEARCH_WATCH_DEFAULT_TENANT_ID"] || env["SEARCH_WATCH_TENANT_ID"]
        end

        def fetch_string(path, default:)
          value = @raw.dig(*path)
          blank?(value) ? default : value.to_s
        end

        def fetch_integer(path, default:)
          value = @raw.dig(*path)
          return default if blank?(value)

          Integer(value)
        rescue ArgumentError, TypeError
          raise ConfigurationError, "#{path.join(".")} must be an integer"
        end

        def fetch_boolean(path, default:)
          value = @raw.dig(*path)
          return default if value.nil?

          case value
          when true, "true", "TRUE", 1, "1" then true
          when false, "false", "FALSE", 0, "0" then false
          else
            raise ConfigurationError, "#{path.join(".")} must be a boolean"
          end
        end

        def retention_policy(path, enabled_default:, ttl_default:)
          enabled = fetch_boolean(path + ["enabled"], default: enabled_default)
          ttl_value = @raw.dig(*(path + ["ttl"]))
          ttl_value = ttl_default if blank?(ttl_value)
          ttl_seconds = ttl_value.nil? ? nil : parse_duration_seconds(ttl_value)

          RetentionPolicy.new(enabled:, ttl_seconds:)
        end

        def parse_duration_seconds(value)
          case value
          when Integer
            value
          when String
            stripped = value.strip
            return Integer(stripped) if stripped.match?(/\A\d+\z/)

            match = stripped.match(/\A(\d+)\s*([smhd])\z/i)
            raise ConfigurationError, "invalid duration #{value.inspect}" unless match

            amount = match[1].to_i
            unit = match[2].downcase
            amount * case unit
                     when "s" then 1
                     when "m" then 60
                     when "h" then 3_600
                     when "d" then 86_400
                     end
          else
            raise ConfigurationError, "invalid duration #{value.inspect}"
          end
        rescue ArgumentError
          raise ConfigurationError, "invalid duration #{value.inspect}"
        end

        def retention_hash(policy)
          {
            "enabled" => policy.enabled,
            "ttl" => policy.ttl_seconds
          }
        end

        def blank?(value)
          value.nil? || value == ""
        end

        def stringify_keys(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, nested), result|
              result[key.to_s] = stringify_keys(nested)
            end
          when Array
            value.map { |nested| stringify_keys(nested) }
          else
            value
          end
        end
      end
    end
  end
end
