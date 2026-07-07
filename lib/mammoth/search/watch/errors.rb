# frozen_string_literal: true

module Mammoth
  module Search
    module Watch
      class Error < StandardError; end
      class ConfigurationError < Error; end
      class PersistenceError < Error; end
    end
  end
end
