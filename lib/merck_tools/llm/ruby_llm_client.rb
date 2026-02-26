# frozen_string_literal: true

module MerckTools
  module LLM
    # Client backed by the ruby_llm gem (supports OpenAI, Anthropic, Gemini, etc.).
    #
    # Requires `gem "ruby_llm"` in the consumer's Gemfile.
    #
    # ENV vars:
    #   OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY
    #   OPENAI_API_BASE  (default: https://api.openai.com/v1)
    #   OPENAI_MODEL / ANTHROPIC_MODEL / AI_MODEL
    #
    class RubyLLMClient < BaseClient
      def initialize(provider: :openai)
        @provider = provider
        @model = case provider
                 when :openai    then ENV.fetch("OPENAI_MODEL",    "gpt-4o-mini")
                 when :anthropic then ENV.fetch("ANTHROPIC_MODEL", "claude-sonnet-4-5-20250514")
                 when :gemini    then ENV.fetch("GEMINI_MODEL")    { ENV.fetch("AI_MODEL", "gemini-2.0-flash") }
                 else                 ENV.fetch("AI_MODEL",        "gpt-4o-mini")
                 end

        require "ruby_llm"
        configure_ruby_llm!
      end

      def generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
        msgs = MerckTools::LLM.normalize_messages(messages)
        raise Error, "No messages provided" if msgs.empty?

        chat = RubyLLM.chat(model: @model, provider: @provider, assume_model_exists: true)
        chat.with_temperature(temperature)

        system_msgs = msgs.select { |m| m[:role] == "system" }
        other_msgs  = msgs.reject { |m| m[:role] == "system" }

        system_msgs.each { |m| chat.with_instructions(m[:content]) }

        if other_msgs.length > 1
          other_msgs[0..-2].each { |m| chat.add_message(role: m[:role].to_sym, content: m[:content]) }
        end

        last_msg = other_msgs.last || msgs.last
        response = chat.ask(last_msg[:content])
        response.content.to_s
      rescue RubyLLM::Error => e
        raise Error, "#{@provider} error: #{e.message}"
      rescue KeyError => e
        raise Error, "#{@provider} not configured: #{e.message}"
      end

      private

      def configure_ruby_llm!
        RubyLLM.configure do |config|
          case @provider
          when :openai
            config.openai_api_key  = ENV.fetch("OPENAI_API_KEY")
            config.openai_api_base = ENV.fetch("OPENAI_API_BASE", "https://api.openai.com/v1")
          when :anthropic
            config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY")
          when :gemini
            config.gemini_api_key = ENV.fetch("GEMINI_API_KEY") { ENV.fetch("GOOGLE_API_KEY") }
          end
        end
      end
    end
  end
end
