# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class Runtime
        attr_reader :configuration, :repository, :webhook_server, :embedded_mammoth

        def initialize(configuration, repository:, webhook_server: nil, embedded_mammoth: nil)
          @configuration = configuration
          @repository = repository
          @webhook_server = webhook_server || WebhookServer.new(configuration, repository:)
          @embedded_mammoth = embedded_mammoth || EmbeddedMammoth.new(configuration)
        end

        def start
          return start_sink_only if configuration.sink_only?

          start_embedded
        ensure
          repository.close if repository.respond_to?(:close)
        end

        private

        def start_sink_only
          webhook_server.start
        end

        def start_embedded
          mammoth_thread = Thread.new do
            embedded_mammoth.start
          end
          mammoth_thread.abort_on_exception = true
          webhook_server.start
        ensure
          mammoth_thread&.kill
        end
      end
    end
  end
end
