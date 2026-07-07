# frozen_string_literal: true

require "json"
require "pg"

module Mammoth
  module Search
    module Watch
      class PostgresRepository
        INSERT_ACTIVITY_SQL = <<~SQL
          INSERT INTO activities (
            tenant_id,
            observation_id,
            sample_id,
            activity_type,
            payload
          ) VALUES ($1, $2, $3, $4, $5::jsonb)
          ON CONFLICT (tenant_id, observation_id, sample_id, activity_type)
          DO UPDATE SET payload = EXCLUDED.payload
          RETURNING id
        SQL

        UPSERT_SEARCH_OBSERVATION_SQL = <<~SQL
          INSERT INTO search_observations (
            tenant_id,
            observation_id,
            response_hash,
            normalized_request,
            normalized_response,
            payload
          ) VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6::jsonb)
          ON CONFLICT (tenant_id, observation_id, response_hash)
          DO UPDATE SET
            normalized_request = EXCLUDED.normalized_request,
            normalized_response = EXCLUDED.normalized_response,
            payload = EXCLUDED.payload
          RETURNING id
        SQL

        UPSERT_SEARCH_DRIFT_SQL = <<~SQL
          INSERT INTO search_drifts (
            tenant_id,
            observation_id,
            response_hash,
            rank,
            title,
            snippet,
            additions,
            removals,
            payload
          ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb)
          ON CONFLICT (tenant_id, observation_id, response_hash)
          DO UPDATE SET
            rank = EXCLUDED.rank,
            title = EXCLUDED.title,
            snippet = EXCLUDED.snippet,
            additions = EXCLUDED.additions,
            removals = EXCLUDED.removals,
            payload = EXCLUDED.payload
          RETURNING id
        SQL

        DELETE_OLDER_THAN_SQL = {
          activities: "DELETE FROM activities WHERE created_at < $1",
          search_observations: "DELETE FROM search_observations WHERE created_at < $1",
          search_drifts: "DELETE FROM search_drifts WHERE created_at < $1"
        }.freeze

        attr_reader :connection

        def initialize(url: nil, connection: nil)
          @connection = connection || PG.connect(url)
        end

        def with_transaction
          connection.exec("BEGIN")
          yield connection
          connection.exec("COMMIT")
        rescue StandardError
          begin
            connection.exec("ROLLBACK")
          rescue StandardError
            nil
          end
          raise
        end

        def insert_activity!(tenant_id:, observation_id:, sample_id:, activity_type:, payload:, connection: self.connection)
          connection.exec_params(
            INSERT_ACTIVITY_SQL,
            [
              tenant_id,
              observation_id,
              sample_id,
              activity_type,
              JSON.generate(payload)
            ]
          )
        rescue PG::Error => e
          raise PersistenceError, e.message
        end

        def upsert_search_observation!(
          tenant_id:,
          observation_id:,
          response_hash:,
          normalized_request:,
          normalized_response:,
          payload:,
          connection: self.connection
        )
          connection.exec_params(
            UPSERT_SEARCH_OBSERVATION_SQL,
            [
              tenant_id,
              observation_id,
              response_hash,
              JSON.generate(normalized_request),
              JSON.generate(normalized_response),
              JSON.generate(payload)
            ]
          )
        rescue PG::Error => e
          raise PersistenceError, e.message
        end

        def upsert_search_drift!(
          tenant_id:,
          observation_id:,
          response_hash:,
          rank:,
          title:,
          snippet:,
          additions:,
          removals:,
          payload:,
          connection: self.connection
        )
          connection.exec_params(
            UPSERT_SEARCH_DRIFT_SQL,
            [
              tenant_id,
              observation_id,
              response_hash,
              rank,
              title,
              snippet,
              JSON.generate(additions),
              JSON.generate(removals),
              JSON.generate(payload)
            ]
          )
        rescue PG::Error => e
          raise PersistenceError, e.message
        end

        def delete_activities_older_than!(cutoff, connection: self.connection)
          delete_older_than!(:activities, cutoff, connection:)
        end

        def delete_search_observations_older_than!(cutoff, connection: self.connection)
          delete_older_than!(:search_observations, cutoff, connection:)
        end

        def delete_search_drifts_older_than!(cutoff, connection: self.connection)
          delete_older_than!(:search_drifts, cutoff, connection:)
        end

        def close
          connection.close unless connection.closed?
        end

        private

        def delete_older_than!(table_name, cutoff, connection:)
          sql = DELETE_OLDER_THAN_SQL.fetch(table_name)
          connection.exec_params(sql, [cutoff])
        rescue PG::Error => e
          raise PersistenceError, e.message
        end
      end
    end
  end
end
