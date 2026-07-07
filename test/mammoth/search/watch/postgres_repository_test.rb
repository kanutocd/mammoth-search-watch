# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeConnection
        attr_reader :queries, :begins, :commits, :rollbacks

        def initialize(result: :ok, closed: false)
          @result = result
          @closed = closed
          @queries = []
          @begins = 0
          @commits = 0
          @rollbacks = 0
        end

        def exec(sql)
          case sql
          when "BEGIN" then @begins += 1
          when "COMMIT" then @commits += 1
          when "ROLLBACK" then @rollbacks += 1
          else
            @queries << [sql, []]
          end
          @result
        end

        def exec_params(query, params)
          @queries << [query, params]
          @result
        end

        def closed?
          @closed
        end

        def close
          @closed = true
        end
      end

      class PostgresRepositoryTest < Minitest::Test
        def test_insert_activity_executes_expected_sql
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)

          repository.insert_activity!(
            tenant_id: "tenant_1",
            observation_id: "obs_1",
            sample_id: "sample_1",
            activity_type: "response",
            payload: { "foo" => "bar" }
          )

          query, params = connection.queries.first
          assert_includes query, "INSERT INTO activities"
          assert_includes query, "ON CONFLICT (tenant_id, observation_id, sample_id, activity_type)"
          assert_equal ["tenant_1", "obs_1", "sample_1", "response", '{"foo":"bar"}'], params
        end

        def test_upsert_search_observation_executes_expected_sql
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)

          repository.upsert_search_observation!(
            tenant_id: "tenant_1",
            observation_id: "obs_1",
            response_hash: "sha256:abc",
            normalized_request: { "q" => "ruby jobs" },
            normalized_response: { "rank" => 1 },
            payload: { "payload" => {} }
          )

          query, params = connection.queries.first
          assert_includes query, "INSERT INTO search_observations"
          assert_equal ["tenant_1", "obs_1", "sha256:abc", '{"q":"ruby jobs"}', '{"rank":1}', '{"payload":{}}'], params
        end

        def test_upsert_search_drift_executes_expected_sql
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)

          repository.upsert_search_drift!(
            tenant_id: "tenant_1",
            observation_id: "obs_1",
            response_hash: "sha256:abc",
            rank: 1,
            title: "Title",
            snippet: "Snippet",
            additions: [{ "url" => "https://example.com" }],
            removals: [],
            payload: { "payload" => {} }
          )

          query, params = connection.queries.first
          assert_includes query, "INSERT INTO search_drifts"
          assert_equal ["tenant_1", "obs_1", "sha256:abc", 1, "Title", "Snippet", '[{"url":"https://example.com"}]', "[]", '{"payload":{}}'],
                       params
        end

        def test_delete_helpers_execute_expected_sql
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)
          cutoff = Time.utc(2026, 7, 7, 0, 0, 0)

          repository.delete_activities_older_than!(cutoff)
          repository.delete_search_observations_older_than!(cutoff)
          repository.delete_search_drifts_older_than!(cutoff)

          assert_equal 3, connection.queries.length
          assert_includes connection.queries[0].first, "DELETE FROM activities"
          assert_includes connection.queries[1].first, "DELETE FROM search_observations"
          assert_includes connection.queries[2].first, "DELETE FROM search_drifts"
        end

        def test_with_transaction_wraps_yielded_work
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)

          repository.with_transaction do |_conn|
            connection.exec_params("SELECT 1", [])
          end

          assert_equal 1, connection.begins
          assert_equal 1, connection.commits
          assert_equal 0, connection.rollbacks
        end

        def test_insert_activity_wraps_pg_errors
          error_class = Class.new(PG::Error)
          connection = Class.new do
            define_method(:exec) do |_sql|
              :ok
            end

            define_method(:exec_params) do |_query, _params|
              raise error_class, "database down"
            end

            define_method(:closed?) { false }
          end.new

          repository = PostgresRepository.new(connection:)

          error = assert_raises(PersistenceError) do
            repository.insert_activity!(
              tenant_id: "tenant_1",
              observation_id: "obs_1",
              sample_id: "sample_1",
              activity_type: "response",
              payload: {}
            )
          end

          assert_match("database down", error.message)
        end

        def test_with_transaction_rolls_back_on_error
          connection = Class.new do
            attr_reader :begins, :commits, :rollbacks

            def initialize
              @begins = 0
              @commits = 0
              @rollbacks = 0
            end

            def exec(sql)
              case sql
              when "BEGIN" then @begins += 1
              when "COMMIT" then @commits += 1
              when "ROLLBACK" then @rollbacks += 1
              end
            end
          end.new
          repository = PostgresRepository.new(connection:)

          assert_raises(RuntimeError) do
            repository.with_transaction do
              raise "boom"
            end
          end

          assert_equal 1, connection.begins
          assert_equal 0, connection.commits
          assert_equal 1, connection.rollbacks
        end

        def test_close_only_closes_open_connections
          connection = FakeConnection.new
          repository = PostgresRepository.new(connection:)

          repository.close

          assert connection.closed?
        end
      end
    end
  end
end
