# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeRetentionRepository
        attr_reader :activities_cutoffs, :observations_cutoffs, :drifts_cutoffs

        def initialize
          @activities_cutoffs = []
          @observations_cutoffs = []
          @drifts_cutoffs = []
        end

        def delete_activities_older_than!(cutoff)
          @activities_cutoffs << cutoff
        end

        def delete_search_observations_older_than!(cutoff)
          @observations_cutoffs << cutoff
        end

        def delete_search_drifts_older_than!(cutoff)
          @drifts_cutoffs << cutoff
        end
      end

      class RetentionCleanerTest < Minitest::Test
        def test_cleans_only_enabled_retention_policies
          configuration = Configuration.new(
            {
              "retention" => {
                "activities" => { "enabled" => true, "ttl" => "1h" },
                "observations" => { "enabled" => true, "ttl" => "2h" },
                "drifts" => { "enabled" => false, "ttl" => "3h" }
              }
            },
            env: {}
          )
          repository = FakeRetentionRepository.new
          cleaner = RetentionCleaner.new(configuration, repository)
          now = Time.utc(2026, 7, 7, 12, 0, 0)

          cleaner.call(now:)

          assert_equal [Time.utc(2026, 7, 7, 11, 0, 0)], repository.activities_cutoffs
          assert_equal [Time.utc(2026, 7, 7, 10, 0, 0)], repository.observations_cutoffs
          assert_empty repository.drifts_cutoffs
        end
      end
    end
  end
end
