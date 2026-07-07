# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeSchedulerCleaner
        attr_reader :calls

        def initialize
          @calls = []
        end

        def call(now:)
          @calls << now
        end
      end

      class RetentionSchedulerTest < Minitest::Test
        def test_runs_cleaner_once_and_sleeps_between_runs
          configuration = Configuration.new(
            {
              "retention" => {
                "scheduler" => { "interval_seconds" => 60 }
              }
            },
            env: {}
          )
          cleaner = FakeSchedulerCleaner.new
          scheduler = RetentionScheduler.new(configuration, cleaner:)
          sleeps = []

          runs = scheduler.call(
            max_runs: 2,
            sleeper: ->(seconds) { sleeps << seconds },
            now: Time.utc(2026, 7, 7, 12, 0, 0)
          )

          assert_equal 2, runs
          assert_equal 2, cleaner.calls.length
          assert_equal [60], sleeps
        end
      end
    end
  end
end
