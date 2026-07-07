# frozen_string_literal: true

require "digest"
require "json"

module Mammoth
  module Search
    module Watch
      class SearchStateDeriver
        attr_reader :repository

        def initialize(repository)
          @repository = repository
        end

        def call(tenant_id:, observation_id:, payload:, connection: nil)
          activity_payload = payload.fetch("payload", payload)
          activity_type = payload["activity_type"] || activity_payload["activity_type"] || "response"
          return unless activity_type == "response"

          response = activity_payload.fetch("response", {})
          return unless response.is_a?(Hash)

          response_hash = response_hash_for(payload:, activity_payload:, response:)
          normalized_request = deep_sort(activity_payload.fetch("request", {}))
          normalized_response = deep_sort(response)
          drift_payload = deep_sort(activity_payload)

          repository.upsert_search_observation!(
            tenant_id: tenant_id,
            observation_id: observation_id,
            response_hash: response_hash,
            normalized_request: normalized_request,
            normalized_response: normalized_response,
            payload: drift_payload,
            connection:
          )

          repository.upsert_search_drift!(
            tenant_id: tenant_id,
            observation_id: observation_id,
            response_hash: response_hash,
            rank: extract_rank(response),
            title: extract_title(response),
            snippet: extract_snippet(response),
            additions: extract_collection(response, "additions"),
            removals: extract_collection(response, "removals"),
            payload: drift_payload,
            connection:
          )
        end

        private

        def response_hash_for(payload:, activity_payload:, response:)
          candidate = response["body_hash"] || response["response_hash"] || payload["response_hash"]
          return candidate unless blank?(candidate)

          digest("response", activity_payload["provider"], response)
        end

        def extract_rank(response)
          value = response["rank"] || response.dig("result", "rank")
          value.nil? ? nil : Integer(value)
        rescue ArgumentError, TypeError
          nil
        end

        def extract_title(response)
          response["title"] || response.dig("result", "title")
        end

        def extract_snippet(response)
          response["snippet"] || response.dig("result", "snippet")
        end

        def extract_collection(response, key)
          value = response[key] || response.dig("diff", key)
          value.is_a?(Array) ? deep_sort(value) : []
        end

        def digest(*parts)
          Digest::SHA256.hexdigest(JSON.generate(parts.map { |part| deep_sort(part) }))
        end

        def deep_sort(value)
          case value
          when Hash
            value.keys.sort.each_with_object({}) do |key, result|
              result[key] = deep_sort(value[key])
            end
          when Array
            value.map { |entry| deep_sort(entry) }
          else
            value
          end
        end

        def blank?(value)
          value.nil? || value == ""
        end
      end
    end
  end
end
