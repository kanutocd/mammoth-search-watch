# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class CLI
        USAGE = [
          "Usage:",
          "  mammoth-search-watch version",
          "  mammoth-search-watch bootstrap [CONFIG]",
          "  mammoth-search-watch retention-cleanup [CONFIG]",
          "  mammoth-search-watch retention-scheduler [CONFIG]",
          "  mammoth-search-watch start [CONFIG]",
          "  mammoth-search-watch validate [CONFIG]"
        ].join("\n")

        def self.call(argv)
          new(argv).call
        end

        attr_reader :argv, :configuration_loader, :runtime_class, :repository_class, :schema_bootstrapper_class,
                    :retention_cleaner_class, :retention_scheduler_class

        def initialize(
          argv,
          configuration_loader: Configuration,
          runtime_class: Runtime,
          repository_class: PostgresRepository,
          schema_bootstrapper_class: SchemaBootstrapper,
          retention_cleaner_class: RetentionCleaner,
          retention_scheduler_class: RetentionScheduler
        )
          @argv = argv
          @configuration_loader = configuration_loader
          @runtime_class = runtime_class
          @repository_class = repository_class
          @schema_bootstrapper_class = schema_bootstrapper_class
          @retention_cleaner_class = retention_cleaner_class
          @retention_scheduler_class = retention_scheduler_class
        end

        def call
          case command
          when nil, "help"
            warn USAGE
            1
          when "version"
            puts "Mammoth Search Watch #{VERSION}"
            0
          when "bootstrap"
            bootstrap
          when "retention-cleanup"
            retention_cleanup
          when "retention-scheduler"
            retention_scheduler
          when "start"
            start
          when "validate"
            validate
          else
            warn USAGE
            1
          end
        rescue Error, StandardError => e
          warn e.message
          1
        end

        private

        def command
          argv.fetch(0, nil)
        end

        def config_path
          argv.fetch(1, nil)
        end

        def start
          bootstrap if configuration.lifecycle.bootstrap_on_start?
          runtime.start
          0
        end

        def bootstrap
          repo = repository
          schema_bootstrapper_class.new(repo.connection).bootstrap!
          0
        ensure
          repo&.close
        end

        def validate
          configuration
          puts "Configuration OK"
          0
        end

        def retention_cleanup
          repo = repository
          retention_cleaner_class.new(configuration, repo).call
          0
        ensure
          repo&.close
        end

        def retention_scheduler
          repo = repository
          cleaner = retention_cleaner_class.new(configuration, repo)
          retention_scheduler_class.new(configuration, cleaner:).call
          0
        ensure
          repo&.close
        end

        def runtime
          runtime_class.new(configuration, repository: repository)
        end

        def repository
          repository_class.new(url: configuration.database_url)
        end

        def configuration
          @configuration ||= configuration_loader.load(config_path)
        end
      end
    end
  end
end
