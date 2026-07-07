# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeDeriverRepository
        attr_reader :observations, :drifts

        def initialize
          @observations = []
          @drifts = []
        end

        def upsert_search_observation!(**kwargs)
          @observations << kwargs
        end

        def upsert_search_drift!(**kwargs)
          @drifts << kwargs
        end
      end

      class SearchStateDeriverTest < Minitest::Test
        def test_derives_observation_and_drift_from_response_payload
          repository = FakeDeriverRepository.new
          deriver = SearchStateDeriver.new(repository)

          deriver.call(
            tenant_id: "tenant_1",
            observation_id: "obs_1",
            payload: {
              "payload" => {
                "request" => { "q" => "ruby jobs", "engine" => "google" },
                "response" => {
                  "body_hash" => "sha256:abc123",
                  "rank" => "1",
                  "title" => "Ruby jobs",
                  "snippet" => "jobs",
                  "additions" => [{ "url" => "https://example.com" }],
                  "removals" => []
                }
              }
            }
          )

          assert_equal 1, repository.observations.length
          assert_equal 1, repository.drifts.length
          assert_equal "sha256:abc123", repository.observations.first[:response_hash]
          assert_equal({ "engine" => "google", "q" => "ruby jobs" }, repository.observations.first[:normalized_request])
          assert_equal 1, repository.drifts.first[:rank]
          assert_equal "Ruby jobs", repository.drifts.first[:title]
          assert_equal "jobs", repository.drifts.first[:snippet]
          assert_equal [{ "url" => "https://example.com" }], repository.drifts.first[:additions]
        end

        def test_skips_non_response_activity_payloads_without_response
          repository = FakeDeriverRepository.new
          deriver = SearchStateDeriver.new(repository)

          result = deriver.call(
            tenant_id: "tenant_1",
            observation_id: "obs_1",
            payload: {
              "activity_type" => "request",
              "payload" => { "request" => { "q" => "ruby jobs" } }
            }
          )

          assert_nil result
          assert_empty repository.observations
          assert_empty repository.drifts
        end
      end
    end
  end
end
