# frozen_string_literal: true

require "json"
require_relative "merck_tools/version"

module MerckTools
  autoload :LLM,        "merck_tools/llm"
  autoload :Auth,       "merck_tools/auth"
  autoload :Jira,       "merck_tools/jira"
  autoload :Confluence, "merck_tools/confluence"
  autoload :MSGraph,    "merck_tools/ms_graph"

  # Load credentials from CredHub on Tanzu/Cloud Foundry.
  #
  # On Tanzu, VCAP_SERVICES contains a JSON blob with bound services.
  # CredHub credentials appear under the "credhub" key, with each
  # credential key/value pair set as an ENV var (uppercased).
  #
  # Call this once at boot (e.g. in config.ru) before instantiating clients:
  #
  #   require "merck_tools"
  #   MerckTools.load_credhub!
  #
  # This replaces the manual parsing pattern:
  #
  #   if ENV.has_key?('VCAP_SERVICES')
  #     env_vars = JSON.parse(ENV['VCAP_SERVICES'])
  #     env_vars['credhub'].first['credentials'].each { |k, v| ENV[k.upcase] = v.to_s }
  #   end
  #
  def self.load_credhub!
    return unless ENV.key?("VCAP_SERVICES")

    vcap = JSON.parse(ENV["VCAP_SERVICES"])
    entries = vcap["credhub"]
    return unless entries.is_a?(Array) && !entries.empty?

    entries.each do |entry|
      creds = entry["credentials"]
      next unless creds.is_a?(Hash)

      creds.each { |k, v| ENV[k.to_s.upcase] = v.to_s }
    end
  end
end
