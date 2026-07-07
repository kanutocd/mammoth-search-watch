# frozen_string_literal: true

require "test_helper"

module Mammoth
  module Search
    module Watch
      class FakeServer
        attr_reader :started, :handled, :init_args

        def initialize(mammoth: nil)
          @mammoth = mammoth
          @started = false
          @handled = []
        end

        def start
          sleep 0.01 until @mammoth.nil? || @mammoth.started
          @started = true
        end

        def init(*args)
          @init_args = args
        end

        def handle(*args)
          @handled << args
        end
      end

      class FakeMammoth
        attr_reader :started

        def initialize
          @started = false
        end

        def start
          @started = true
        end
      end

      class RuntimeTest < Minitest::Test
        def test_sink_only_mode_starts_webhook_server_only
          configuration = Configuration.new({ "runtime" => { "mode" => "sink" } }, env: {})
          server = FakeServer.new
          mammoth = FakeMammoth.new
          runtime = Runtime.new(configuration, repository: Object.new, webhook_server: server, embedded_mammoth: mammoth)

          runtime.start

          assert server.started
          refute mammoth.started
        end

        def test_embedded_mode_starts_embedded_mammoth_and_webhook_server
          configuration = Configuration.new({}, env: {})
          mammoth = FakeMammoth.new
          server = FakeServer.new(mammoth:)
          runtime = Runtime.new(configuration, repository: Object.new, webhook_server: server, embedded_mammoth: mammoth)

          runtime.start

          assert server.started
          assert mammoth.started
        end

        def test_runtime_closes_repository_after_failure
          configuration = Configuration.new({ "runtime" => { "mode" => "sink" } }, env: {})
          repository = Struct.new(:closed) do
            def close
              self.closed = true
            end
          end.new(false)
          server = Class.new do
            def start
              raise "boom"
            end
          end.new

          runtime = Runtime.new(configuration, repository:, webhook_server: server, embedded_mammoth: FakeMammoth.new)

          assert_raises(RuntimeError) do
            runtime.start
          end

          assert repository.closed
        end
      end
    end
  end
end
