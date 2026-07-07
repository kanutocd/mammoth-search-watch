# frozen_string_literal: true

require "simplecov"

SimpleCov.external_at_exit = true
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
  minimum_coverage line: 99, branch: 99
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "mammoth/search/watch"

require "minitest/autorun"
