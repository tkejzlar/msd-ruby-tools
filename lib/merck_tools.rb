# frozen_string_literal: true

require_relative "merck_tools/version"

module MerckTools
  autoload :LLM,        "merck_tools/llm"
  autoload :Auth,       "merck_tools/auth"
  autoload :Jira,       "merck_tools/jira"
  autoload :Confluence, "merck_tools/confluence"
  autoload :MSGraph,    "merck_tools/ms_graph"
end
