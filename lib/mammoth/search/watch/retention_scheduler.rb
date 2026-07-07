# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class RetentionScheduler
        attr_reader :configuration, :cleaner

        def initialize(configuration, cleaner:)
          @configuration = configuration
          @cleaner = cleaner
        end

        def call(max_runs: nil, sleeper: Kernel.method(:sleep), now: Time.now.utc)
          runs = 0

          loop do
            cleaner.call(now:)
            runs += 1
            break if max_runs && runs >= max_runs

            sleeper.call(configuration.retention.scheduler.interval_seconds)
          end

          runs
        end
      end
    end
  end
end
