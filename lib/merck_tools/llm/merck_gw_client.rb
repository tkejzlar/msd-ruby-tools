# frozen_string_literal: true

require "json"
require "faraday"

module MerckTools
  module LLM
    # Merck internal Azure-OpenAI gateway.
    #
    # Uses a custom URL pattern and X-Merck-APIKey header (not Bearer).
    #
    # ENV vars:
    #   GW_API_ROOT       – base URL  (default: https://iapi-test.merck.com/gpt/v2)
    #   GW_API_VERSION    – api-version query param (default: 2025-04-14)
    #   GW_MODEL          – deployment / model name
    #   MERCK_GW_API_KEY  – API key  (fallback: X_MERCK_APIKEY, MERCK_API_KEY)
    #   GW_API_HEADER     – header name (default: X-Merck-APIKey)
    #   AI_HTTP_TIMEOUT   – read timeout in seconds (default: 300)
    #
    class MerckGwClient < BaseClient
      attr_reader :api_root, :api_version, :model, :api_header

      def initialize(
        api_root:    ENV.fetch("GW_API_ROOT")    { ENV.fetch("MERCK_API_ROOT", "https://iapi-test.merck.com/gpt/v2") },
        api_version: ENV.fetch("GW_API_VERSION") { ENV.fetch("MERCK_API_VERSION", "2025-04-14") },
        model:       ENV.fetch("GW_MODEL")       { ENV.fetch("MERCK_DEPLOYMENT") { ENV.fetch("OPENAI_MODEL", "gpt-4o-mini") } },
        api_key:     ENV.fetch("MERCK_GW_API_KEY") { ENV.fetch("X_MERCK_APIKEY") { ENV.fetch("MERCK_API_KEY") } },
        api_header:  ENV.fetch("GW_API_HEADER")  { ENV.fetch("MERCK_API_HEADER", "X-Merck-APIKey") },
        timeout:     Integer(ENV.fetch("AI_HTTP_TIMEOUT", "300"))
      )
        @api_root    = api_root.to_s.chomp("/")
        @api_version = api_version.to_s
        @model       = model.to_s
        @api_key     = api_key.to_s
        @api_header  = api_header.to_s
        @conn = Faraday.new do |f|
          f.options.timeout      = timeout
          f.options.open_timeout = 30
          f.adapter Faraday.default_adapter
        end
      end

      def generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
        msgs = MerckTools::LLM.normalize_messages(messages)
        raise Error, "No messages provided" if msgs.empty?

        payload = {
          model:                  @model,
          messages:               msgs,
          temperature:            temperature.to_f,
          max_completion_tokens:  max_tokens.to_i
        }
        payload[:response_format] = { type: "json_object" } if json

        last_error = nil
        candidate_urls.each do |url|
          resp = @conn.post(url) do |req|
            req.params["api-version"] = @api_version unless @api_version.empty?
            req.headers["Content-Type"] = "application/json"
            req.headers[@api_header]    = @api_key
            req.body = payload.to_json
          end

          unless resp.success?
            last_error = Error.new("Merck GW #{resp.status}: #{resp.body.to_s[0..500]}")
            next if resp.status == 404
            raise last_error
          end

          parsed = JSON.parse(resp.body) rescue {}
          return parsed.dig("choices", 0, "message", "content").to_s
        rescue Error
          raise
        rescue StandardError => e
          last_error = e
          next
        end

        raise last_error || Error.new("Merck GW: no successful response from any URL pattern")
      end

      private

      def candidate_urls
        [
          "#{@api_root}/#{@model}/chat/completions",
          "#{@api_root}/deployments/#{@model}/chat/completions",
          "#{@api_root}/openai/deployments/#{@model}/chat/completions"
        ].uniq
      end
    end
  end
end
