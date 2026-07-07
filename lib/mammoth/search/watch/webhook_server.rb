# frozen_string_literal: true

require "agoo"
require "json"
require "securerandom"

module Mammoth
  module Search
    module Watch
      class WebhookServer
        attr_reader :configuration, :repository, :tenant_resolver, :deriver

        def initialize(configuration, repository:, tenant_resolver: TenantResolver.new(configuration), deriver: nil)
          @configuration = configuration
          @repository = repository
          @tenant_resolver = tenant_resolver
          @deriver = deriver || SearchStateDeriver.new(repository)
        end

        def start(server: Agoo::Server)
          server.init(
            configuration.webhook.port,
            configuration.webhook.host,
            thread_count: configuration.webhook.threads,
            root: configuration.webhook.root
          )
          server.handle(:POST, configuration.webhook.path, method(:handle_search_watch))
          server.start
        end

        def handle_search_watch(request)
          payload = JSON.parse(read_body(request))
          tenant_id = tenant_resolver.call(request, payload)
          sample_id = payload.fetch("sample_id", SecureRandom.uuid)
          activity_type = payload.fetch("activity_type", "response")

          repository.with_transaction do |connection|
            repository.insert_activity!(
              tenant_id: tenant_id,
              observation_id: payload.fetch("observation_id"),
              sample_id: sample_id,
              activity_type: activity_type,
              payload: payload,
              connection:
            )

            if activity_type == "response"
              deriver.call(
                tenant_id: tenant_id,
                observation_id: payload.fetch("observation_id"),
                payload: payload,
                connection:
              )
            end
          end

          accepted_response
        rescue ConfigurationError, KeyError, JSON::ParserError => e
          bad_request_response(e.message)
        rescue StandardError => e
          internal_error_response(e.class.name)
        end

        private

        def read_body(request)
          body = request.respond_to?(:body) ? request.body : request
          return body.read if body.respond_to?(:read)

          body.to_s
        end

        def accepted_response
          [202, { "content-type" => "application/json" }, ['{"status":"accepted"}']]
        end

        def bad_request_response(message)
          [400, { "content-type" => "application/json" }, [{ error: message }.to_json]]
        end

        def internal_error_response(message)
          [500, { "content-type" => "application/json" }, [{ error: message }.to_json]]
        end
      end
    end
  end
end
