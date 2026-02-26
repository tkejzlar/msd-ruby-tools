# frozen_string_literal: true

module MerckTools
  module LLM
    class MockClient < BaseClient
      def generate(messages:, temperature: 0.2, max_tokens: 900, json: false)
        msgs = MerckTools::LLM.normalize_messages(messages)
        last_user = msgs.reverse.find { |m| m[:role] == "user" }&.dig(:content) || "(no question)"
        <<~TXT
          **Mock AI (not configured)**

          Set `AI_PROVIDER` in `.env` to one of: `openai`, `anthropic`, `merck_gw`, or `ruby_llm`.

          Your question:
          #{last_user}
        TXT
      end
    end
  end
end
