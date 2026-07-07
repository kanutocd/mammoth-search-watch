# frozen_string_literal: true

require "test_helper"
require "stringio"

module Mammoth
  module Search
    module Watch
      class FakeConfiguration
        Lifecycle = Struct.new(:bootstrap_on_start, keyword_init: true) do
          def bootstrap_on_start?
            bootstrap_on_start
          end
        end

        attr_reader :database_url, :lifecycle

        def initialize(database_url:, bootstrap_on_start: true)
          @database_url = database_url
          @lifecycle = Lifecycle.new(bootstrap_on_start:)
        end
      end

      class FakeLoader
        attr_reader :path

        def initialize(configuration)
          @configuration = configuration
        end

        def load(path)
          @path = path
          @configuration
        end
      end

      class FakeRepositoryClass
        class << self
          attr_accessor :last_url

          def new(url:)
            self.last_url = url
            Struct.new(:connection, :closed) do
              def close
                self.closed = true
              end
            end.new(Object.new, false)
          end
        end
      end

      class FakeBootstrapperClass
        class << self
          attr_accessor :last_connection, :started

          def new(connection)
            self.last_connection = connection
            Object.new.tap do |instance|
              instance.define_singleton_method(:bootstrap!) do
                FakeBootstrapperClass.started = true
              end
            end
          end
        end
      end

      class FakeRetentionSchedulerClass
        class << self
          attr_accessor :last_configuration, :last_cleaner, :started

          def new(configuration, cleaner:)
            self.last_configuration = configuration
            self.last_cleaner = cleaner
            Object.new.tap do |instance|
              instance.define_singleton_method(:call) do
                FakeRetentionSchedulerClass.started = true
              end
            end
          end
        end
      end

      class FakeRuntimeClass
        class << self
          attr_accessor :last_configuration, :last_repository, :started

          def new(configuration, repository:)
            self.last_configuration = configuration
            self.last_repository = repository
            Object.new.tap do |instance|
              instance.define_singleton_method(:start) do
                FakeRuntimeClass.started = true
              end
            end
          end
        end
      end

      class FakeRepositoryWithTransaction
        attr_reader :connection, :closed, :transactions

        def initialize
          @connection = Object.new
          @closed = false
          @transactions = 0
        end

        def with_transaction
          @transactions += 1
          yield connection
        end

        def close
          @closed = true
        end
      end

      class CLITest < Minitest::Test
        def setup
          FakeRepositoryClass.last_url = nil
          FakeRuntimeClass.last_configuration = nil
          FakeRuntimeClass.last_repository = nil
          FakeRuntimeClass.started = false
          FakeBootstrapperClass.last_connection = nil
          FakeBootstrapperClass.started = false
          FakeRetentionSchedulerClass.last_configuration = nil
          FakeRetentionSchedulerClass.last_cleaner = nil
          FakeRetentionSchedulerClass.started = false
        end

        def test_version_reports_gem_version
          stdout, _stderr = capture_io do
            assert_equal 0, CLI.new(["version"]).call
          end

          assert_match(VERSION, stdout)
        end

        def test_missing_command_returns_usage_error
          _stdout, stderr = capture_io do
            assert_equal 1, CLI.new([]).call
          end

          assert_match("Usage:", stderr)
        end

        def test_validate_loads_configuration
          loader = FakeLoader.new(FakeConfiguration.new(database_url: "postgres://example"))
          cli = CLI.new(["validate", "/tmp/search_watch.yml"], configuration_loader: loader)

          stdout, _stderr = capture_io do
            assert_equal 0, cli.call
          end

          assert_equal "/tmp/search_watch.yml", loader.path
          assert_match("Configuration OK", stdout)
        end

        def test_start_builds_runtime_with_database_url
          loader = FakeLoader.new(FakeConfiguration.new(database_url: "postgres://example"))
          cli = CLI.new(
            ["start", "/tmp/search_watch.yml"],
            configuration_loader: loader,
            runtime_class: FakeRuntimeClass,
            repository_class: FakeRepositoryClass,
            schema_bootstrapper_class: FakeBootstrapperClass
          )

          assert_equal 0, cli.call
          assert_equal "postgres://example", FakeRepositoryClass.last_url
          assert_equal loader.instance_variable_get(:@configuration), FakeRuntimeClass.last_configuration
          assert FakeRuntimeClass.started
          assert_equal "/tmp/search_watch.yml", loader.path
        end

        def test_bootstrap_invokes_schema_bootstrapper
          loader = FakeLoader.new(FakeConfiguration.new(database_url: "postgres://example"))
          cli = CLI.new(
            ["bootstrap", "/tmp/search_watch.yml"],
            configuration_loader: loader,
            repository_class: FakeRepositoryClass,
            schema_bootstrapper_class: FakeBootstrapperClass
          )

          assert_equal 0, cli.call
          assert_equal "postgres://example", FakeRepositoryClass.last_url
          assert FakeBootstrapperClass.started
          assert_instance_of Object, FakeBootstrapperClass.last_connection
        end

        def test_retention_cleanup_invokes_retention_cleaner
          loader = FakeLoader.new(FakeConfiguration.new(database_url: "postgres://example"))
          cleaner_class = Class.new do
            class << self
              attr_accessor :last_configuration, :last_repository, :started
            end

            def initialize(configuration, repository)
              self.class.last_configuration = configuration
              self.class.last_repository = repository
            end

            def call
              self.class.started = true
            end
          end

          cli = CLI.new(
            ["retention-cleanup", "/tmp/search_watch.yml"],
            configuration_loader: loader,
            repository_class: FakeRepositoryClass,
            retention_cleaner_class: cleaner_class
          )

          assert_equal 0, cli.call
          assert_equal "postgres://example", FakeRepositoryClass.last_url
          assert cleaner_class.started
          assert_equal loader.instance_variable_get(:@configuration), cleaner_class.last_configuration
        end

        def test_retention_scheduler_invokes_scheduler
          loader = FakeLoader.new(FakeConfiguration.new(database_url: "postgres://example"))
          cli = CLI.new(
            ["retention-scheduler", "/tmp/search_watch.yml"],
            configuration_loader: loader,
            repository_class: FakeRepositoryClass,
            retention_scheduler_class: FakeRetentionSchedulerClass
          )

          assert_equal 0, cli.call
          assert_equal "postgres://example", FakeRepositoryClass.last_url
          assert FakeRetentionSchedulerClass.started
          assert_equal loader.instance_variable_get(:@configuration), FakeRetentionSchedulerClass.last_configuration
          assert FakeRetentionSchedulerClass.last_cleaner
        end

        def test_validate_returns_error_when_loader_fails
          loader = Class.new do
            def load(_path)
              raise ConfigurationError, "broken config"
            end
          end.new

          _stdout, stderr = capture_io do
            assert_equal 1, CLI.new(["validate", "/tmp/search_watch.yml"], configuration_loader: loader).call
          end

          assert_match("broken config", stderr)
        end
      end
    end
  end
end
