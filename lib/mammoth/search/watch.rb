# frozen_string_literal: true

require_relative "watch/version"
require_relative "watch/errors"
require_relative "watch/configuration"
require_relative "watch/tenant_resolver"
require_relative "watch/postgres_repository"
require_relative "watch/schema_bootstrapper"
require_relative "watch/search_state_deriver"
require_relative "watch/retention_cleaner"
require_relative "watch/retention_scheduler"
require_relative "watch/embedded_mammoth"
require_relative "watch/webhook_server"
require_relative "watch/runtime"
require_relative "watch/cli"

module Mammoth
  module Search
    module Watch
    end
  end
end
