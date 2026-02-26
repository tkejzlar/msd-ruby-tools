# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module MerckTools
  module LLM
    # Direct OpenAI chat-completions client (no ruby_llm dependency).
    #
    # ENV vars:
    #   OPENAI_API_KEY   – API key
    #   OPENAI_API_BASE  – base URL (default: https://api.openai.com)
    #   OPENAI_MODEL     – model (default: gpt-4o-mini)
    #   HTTP_READ_TIMEOUT / HTTP_OPEN_TIMEOUT – timeouts in seconds
    #
    class OpenAIClient < BaseClient
      def initialize(
        api_key:      ENV.fetch("OPENAI_API_KEY"),
        api_base:     ENV.fetch("OPENAI_API_BASE", "https://api.openai.com"),
        model:        ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"),
        read_timeout: Integer(ENV.fetch("HTTP_READ_TIMEOUT", "600")),
        open_timeout: Integer(ENV.fetch("HTTP_OPEN_TIMEOUT", "30"))
      )
        @api_key      = api_key
        @api_base     = api_base.to_s.chomp("/")
        @model        = model
        @read_timeout = read_timeout
        @open_timeout = open_timeout
      end

      def generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
        msgs = MerckTools::LLM.normalize_messages(messages)
        raise Error, "No messages provided" if msgs.empty?

        uri = URI("#{@api_base}/v1/chat/completions")
        body = { model: @model, messages: msgs, temperature: temperature.to_f }
        body[max_tokens_key] = max_tokens.to_i
        body[:response_format] = { type: "json_object" } if json

        res = post_json(uri, body)
        raise Error, "OpenAI #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

        begin
          parsed = JSON.parse(res.body)
        rescue JSON::ParserError
          raise Error, "OpenAI: invalid JSON response"
        end
        parsed.dig("choices", 0, "message", "content").to_s
      end

      def stream(messages:, temperature: 0.2, max_tokens: 900, json: false, &block)
        msgs = MerckTools::LLM.normalize_messages(messages)
        raise Error, "No messages provided" if msgs.empty?

        uri = URI("#{@api_base}/v1/chat/completions")
        body = { model: @model, messages: msgs, temperature: temperature.to_f, stream: true }
        body[max_tokens_key] = max_tokens.to_i
        body[:response_format] = { type: "json_object" } if json

        buffer = +""
        req = build_request(uri, body)
        http = build_http(uri)

        http.request(req) do |res|
          raise Error, "OpenAI stream #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)
          res.read_body do |chunk|
            buffer << chunk
            while (line = buffer.slice!(/.*\n/))
              ln = line.strip
              next if ln.empty? || ln.start_with?(":") || !ln.start_with?("data:")
              data = ln.sub(/^data:\s*/, "")
              return if data == "[DONE]"
              begin
                obj = JSON.parse(data)
              rescue JSON::ParserError
                next
              end
              delta = obj.dig("choices", 0, "delta", "content")
              yield delta if delta && block
            end
          end
        end
      end

      private

      # Reasoning-series models (o1, o3, o4, …) require max_completion_tokens;
      # classic GPT models use max_tokens.
      def max_tokens_key
        @model.match?(/\A(o[0-9])/) ? :max_completion_tokens : :max_tokens
      end

      def post_json(uri, body)
        req = build_request(uri, body)
        build_http(uri).request(req)
      end

      def build_request(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"]  = "application/json"
        req["Authorization"] = "Bearer #{@api_key}"
        req.body = body.to_json
        req
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.read_timeout = @read_timeout
        http.open_timeout = @open_timeout
        http
      end
    end
  end
end
