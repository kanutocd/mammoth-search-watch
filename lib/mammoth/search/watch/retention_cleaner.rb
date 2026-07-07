# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class RetentionCleaner
        attr_reader :configuration, :repository

        def initialize(configuration, repository)
          @configuration = configuration
          @repository = repository
        end

        def call(now: Time.now.utc)
          clean_activities(now:) if configuration.retention.activities.enabled?
          clean_search_observations(now:) if configuration.retention.observations.enabled?
          clean_search_drifts(now:) if configuration.retention.drifts.enabled?
        end

        private

        def clean_activities(now:)
          ttl = configuration.retention.activities.ttl_seconds
          return unless ttl

          repository.delete_activities_older_than!(now - ttl)
        end

        def clean_search_observations(now:)
          ttl = configuration.retention.observations.ttl_seconds
          return unless ttl

          repository.delete_search_observations_older_than!(now - ttl)
        end

        def clean_search_drifts(now:)
          ttl = configuration.retention.drifts.ttl_seconds
          return unless ttl

          repository.delete_search_drifts_older_than!(now - ttl)
        end
      end
    end
  end
end
