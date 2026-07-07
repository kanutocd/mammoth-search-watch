# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class SchemaBootstrapper
        ACTIVITY_TYPE_SQL = <<~SQL
          DO $$
          BEGIN
            IF NOT EXISTS (
              SELECT 1
              FROM pg_type
              JOIN pg_namespace ON pg_namespace.oid = pg_type.typnamespace
              WHERE pg_type.typname = 'activity_type'
                AND pg_namespace.nspname = current_schema()
            ) THEN
              CREATE TYPE activity_type AS ENUM ('request', 'response');
            END IF;
          END
          $$;
        SQL

        ACTIVITY_POLICY_NAME = "tenant_isolation_policy"

        attr_reader :connection

        def initialize(connection)
          @connection = connection
        end

        def bootstrap!
          ensure_activity_type!
          create_activities_table!
          create_search_observations_table!
          create_search_drifts_table!
          enable_tenant_row_level_security!
          create_tenant_policies!
          self
        end

        private

        def ensure_activity_type!
          connection.exec(ACTIVITY_TYPE_SQL)
        end

        def create_activities_table!
          connection.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS activities (
              id BIGSERIAL PRIMARY KEY,
              tenant_id TEXT NOT NULL,
              observation_id TEXT NOT NULL,
              sample_id TEXT NOT NULL,
              activity_type activity_type NOT NULL,
              payload JSONB NOT NULL,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              UNIQUE (tenant_id, observation_id, sample_id, activity_type)
            );
          SQL
        end

        def create_search_observations_table!
          connection.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS search_observations (
              id BIGSERIAL PRIMARY KEY,
              tenant_id TEXT NOT NULL,
              observation_id TEXT NOT NULL,
              response_hash TEXT NOT NULL,
              normalized_request JSONB NOT NULL DEFAULT '{}'::jsonb,
              normalized_response JSONB NOT NULL DEFAULT '{}'::jsonb,
              payload JSONB NOT NULL,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              UNIQUE (tenant_id, observation_id, response_hash)
            );
          SQL
        end

        def create_search_drifts_table!
          connection.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS search_drifts (
              id BIGSERIAL PRIMARY KEY,
              tenant_id TEXT NOT NULL,
              observation_id TEXT NOT NULL,
              response_hash TEXT NOT NULL,
              rank INTEGER,
              title TEXT,
              snippet TEXT,
              additions JSONB NOT NULL DEFAULT '[]'::jsonb,
              removals JSONB NOT NULL DEFAULT '[]'::jsonb,
              payload JSONB NOT NULL,
              created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
              UNIQUE (tenant_id, observation_id, response_hash)
            );
          SQL
        end

        def enable_tenant_row_level_security!
          %w[activities search_observations search_drifts].each do |table_name|
            connection.exec("ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;")
            connection.exec("ALTER TABLE #{table_name} FORCE ROW LEVEL SECURITY;")
          end
        end

        def create_tenant_policies!
          %w[activities search_observations search_drifts].each do |table_name|
            create_policy_if_missing!(table_name)
          end
        end

        def create_policy_if_missing!(table_name)
          exists = connection.exec_params(
            <<~SQL,
              SELECT 1
              FROM pg_policies
              WHERE schemaname = current_schema()
                AND tablename = $1
                AND policyname = $2
              LIMIT 1;
            SQL
            [table_name, ACTIVITY_POLICY_NAME]
          ).ntuples.positive?

          return if exists

          connection.exec(<<~SQL)
            CREATE POLICY #{ACTIVITY_POLICY_NAME}
            ON #{table_name}
            USING (tenant_id = current_setting('app.current_tenant_id', true))
            WITH CHECK (tenant_id = current_setting('app.current_tenant_id', true));
          SQL
        end
      end
    end
  end
end
