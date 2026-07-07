# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeResult
        attr_reader :ntuples

        def initialize(ntuples)
          @ntuples = ntuples
        end
      end

      class FakeBootstrapConnection
        attr_reader :exec_calls, :exec_params_calls

        def initialize(policy_exists: false)
          @policy_exists = policy_exists
          @exec_calls = []
          @exec_params_calls = []
        end

        def exec(sql)
          @exec_calls << sql
          FakeResult.new(0)
        end

        def exec_params(sql, params)
          @exec_params_calls << [sql, params]
          FakeResult.new(@policy_exists ? 1 : 0)
        end
      end

      class SchemaBootstrapperTest < Minitest::Test
        def test_bootstrap_creates_tables_and_policies
          connection = FakeBootstrapConnection.new

          SchemaBootstrapper.new(connection).bootstrap!

          assert(connection.exec_calls.any? { |sql| sql.include?("CREATE TYPE activity_type AS ENUM") })
          assert(connection.exec_calls.any? { |sql| sql.include?("CREATE TABLE IF NOT EXISTS activities") })
          assert(connection.exec_calls.any? { |sql| sql.include?("CREATE TABLE IF NOT EXISTS search_observations") })
          assert(connection.exec_calls.any? { |sql| sql.include?("CREATE TABLE IF NOT EXISTS search_drifts") })
          assert(connection.exec_calls.any? { |sql| sql.include?("ENABLE ROW LEVEL SECURITY") })
          assert(connection.exec_calls.any? { |sql| sql.include?("CREATE POLICY tenant_isolation_policy") })
          assert_equal 3, connection.exec_params_calls.length
        end

        def test_bootstrap_skips_policy_creation_when_policy_exists
          connection = FakeBootstrapConnection.new(policy_exists: true)

          SchemaBootstrapper.new(connection).bootstrap!

          refute(connection.exec_calls.any? { |sql| sql.include?("CREATE POLICY tenant_isolation_policy") })
          assert_equal 3, connection.exec_params_calls.length
        end
      end
    end
  end
end
