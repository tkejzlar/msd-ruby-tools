# frozen_string_literal: true

module MerckTools
  module LLM
    class BaseClient
      def generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
        raise NotImplementedError, "#{self.class}#generate must be implemented"
      end

      def stream(messages:, temperature: 0.2, max_tokens: 900, json: false, &block)
        # Default: generate full response and yield it as a single chunk
        text = generate(messages: messages, temperature: temperature, max_tokens: max_tokens, json: json)
        yield text if block
        text
      end
    end
  end
end
