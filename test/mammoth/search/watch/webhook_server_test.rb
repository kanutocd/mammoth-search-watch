# frozen_string_literal: true

require "test_helper"
require "stringio"
require "json"

module Mammoth
  module Search
    module Watch
      class FakeRepository
        attr_reader :calls, :observations, :drifts, :transactions

        def initialize(error: nil)
          @error = error
          @calls = []
          @observations = []
          @drifts = []
          @transactions = 0
        end

        def with_transaction
          @transactions += 1
          yield Object.new
        end

        def insert_activity!(**kwargs)
          raise @error if @error

          @calls << kwargs
        end

        def upsert_search_observation!(**kwargs)
          @observations << kwargs
        end

        def upsert_search_drift!(**kwargs)
          @drifts << kwargs
        end
      end

      class FakeRequest
        attr_reader :body, :headers

        def initialize(body:, headers: {})
          @body = StringIO.new(body)
          @headers = headers
        end
      end

      class WebhookServerTest < Minitest::Test
        def test_handle_search_watch_persists_payload_and_returns_accepted
          configuration = Configuration.new({}, env: {})
          repository = FakeRepository.new
          server = WebhookServer.new(configuration, repository:)

          response = server.handle_search_watch(
            FakeRequest.new(
              body: {
                "observation_id" => "obs_1",
                "tenant_id" => "tenant_payload",
                "payload" => { "hello" => "world" }
              }.to_json
            )
          )

          assert_equal 202, response.first
          assert_equal "application/json", response[1]["content-type"]
          assert_equal 1, repository.calls.length
          assert_equal "tenant_payload", repository.calls.first[:tenant_id]
          assert_equal "obs_1", repository.calls.first[:observation_id]
          assert_equal "response", repository.calls.first[:activity_type]
          assert_equal({ "hello" => "world" }, repository.calls.first[:payload]["payload"])
          assert_match(/\A[0-9a-f-]{36}\z/, repository.calls.first[:sample_id])
          assert_equal 1, repository.transactions
          assert_equal 1, repository.observations.length
          assert_equal 1, repository.drifts.length
          assert_equal "obs_1", repository.observations.first[:observation_id]
          assert_equal "obs_1", repository.drifts.first[:observation_id]
        end

        def test_handle_search_watch_returns_bad_request_for_invalid_json
          configuration = Configuration.new({}, env: {})
          repository = FakeRepository.new
          server = WebhookServer.new(configuration, repository:)

          response = server.handle_search_watch(FakeRequest.new(body: "{"))

          assert_equal 400, response.first
          assert_match("expected object key", response.last.first)
          assert_empty repository.calls
        end

        def test_handle_search_watch_returns_internal_error_for_repository_failure
          configuration = Configuration.new({}, env: {})
          repository = FakeRepository.new(error: RuntimeError.new("boom"))
          server = WebhookServer.new(configuration, repository:)

          response = server.handle_search_watch(
            FakeRequest.new(
              body: {
                "observation_id" => "obs_1",
                "tenant_id" => "tenant_1"
              }.to_json
            )
          )

          assert_equal 500, response.first
          assert_match("RuntimeError", response.last.first)
        end
      end
    end
  end
end
