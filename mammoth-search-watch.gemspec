# frozen_string_literal: true

require_relative "lib/mammoth/search/watch/version"

Gem::Specification.new do |spec|
  spec.name = "mammoth-search-watch"
  spec.version = Mammoth::Search::Watch::VERSION
  spec.authors = ["Kenneth C. Demanawa"]
  spec.email = ["kenneth.c.demanawa@gmail.com"]

  spec.summary = "SERP observation and drift capture built on the Mammoth data plane."
  spec.description = <<~DESCRIPTION.strip
    Mammoth Search Watch captures SERP request and response observations,
    persists them as PostgreSQL facts, and lets Mammoth deliver resulting WAL-backed
    change events. It is intentionally PostgreSQL-first, WAL-centric, and built as
    a Mammoth descendant rather than a generic HTTP event bus.
  DESCRIPTION

  spec.homepage = "https://github.com/kanutocd/mammoth-search-watch"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/kanutocd/mammoth-search-watch/issues",
    "changelog_uri" => "https://github.com/kanutocd/mammoth-search-watch/blob/main/CHANGELOG.md",
    "documentation_uri" => "https://github.com/kanutocd/mammoth-search-watch#readme",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true",
    "source_code_uri" => spec.homepage
  }

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "agoo", "~> 2.15"
  spec.add_dependency "mammoth", "~> 0.7"
end
