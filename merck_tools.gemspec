# frozen_string_literal: true

require_relative "lib/merck_tools/version"

Gem::Specification.new do |spec|
  spec.name          = "merck_tools"
  spec.version       = MerckTools::VERSION
  spec.authors       = ["tkejzlar"]
  spec.summary       = "Shared clients for Merck internal APIs (LLM gateway, OAuth SSO, Jira, Confluence, MS Graph, SharePoint)"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir["lib/**/*.rb", "merck_tools.gemspec"]
  spec.require_paths = ["lib"]

  # HTTP — Faraday is used by the Merck GW LLM client; rest-client by Jira/Confluence
  spec.add_dependency "faraday", ">= 1.0"
  spec.add_dependency "rest-client", ">= 2.0"
  spec.add_dependency "json"

  # Optional at runtime — consumers pull in ruby_llm only if they use the
  # OpenAI / Anthropic / Gemini providers.  We don't force it here.

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
end
