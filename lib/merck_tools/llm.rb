# frozen_string_literal: true

require_relative "llm/base_client"
require_relative "llm/merck_gw_client"
require_relative "llm/openai_client"
require_relative "llm/ruby_llm_client"
require_relative "llm/mock_client"

module MerckTools
  module LLM
    class Error < StandardError; end

    # Factory — reads AI_PROVIDER / LLM_PROVIDER from ENV and returns
    # the appropriate client.  Every client responds to:
    #
    #   client.generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
    #   #=> String
    #
    def self.build_from_env(provider: nil)
      provider ||= (ENV["AI_PROVIDER"] || ENV["LLM_PROVIDER"] || "mock").to_s.downcase.strip
      case provider
      when "merck_gw", "gw"           then MerckGwClient.new
      when "openai"                    then OpenAIClient.new
      when "anthropic"                 then RubyLLMClient.new(provider: :anthropic)
      when "ruby_llm", "ruby-llm"     then RubyLLMClient.new(provider: detect_ruby_llm_provider)
      when "mock", ""                  then MockClient.new
      else                                  MockClient.new
      end
    end

    # Normalize message hashes that may use string or symbol keys.
    def self.normalize_messages(messages)
      Array(messages).filter_map do |m|
        next unless m.is_a?(Hash)
        role    = m[:role] || m["role"]
        content = m[:content] || m["content"]
        next if role.to_s.strip.empty? || content.to_s.strip.empty?
        { role: role.to_s, content: content.to_s }
      end
    end

    def self.detect_ruby_llm_provider
      model = (ENV["AI_MODEL"] || ENV["OPENAI_MODEL"] || "").to_s
      if model.start_with?("claude")
        :anthropic
      elsif model.start_with?("gemini")
        :gemini
      else
        :openai
      end
    end
    private_class_method :detect_ruby_llm_provider
  end
end
