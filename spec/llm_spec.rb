# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::LLM do
  describe ".build_from_env" do
    it "returns MockClient when no provider is set" do
      stub_env("AI_PROVIDER" => nil, "LLM_PROVIDER" => nil)
      client = described_class.build_from_env
      expect(client).to be_a(MerckTools::LLM::MockClient)
    end

    it "returns MerckGwClient for merck_gw provider" do
      stub_env(
        "AI_PROVIDER"     => "merck_gw",
        "GW_API_ROOT"     => "https://test.example.com/gpt/v2",
        "MERCK_GW_API_KEY" => "test-key",
        "GW_MODEL"        => "gpt-4o"
      )
      client = described_class.build_from_env
      expect(client).to be_a(MerckTools::LLM::MerckGwClient)
    end

    it "returns OpenAIClient for openai provider" do
      stub_env("AI_PROVIDER" => "openai", "OPENAI_API_KEY" => "sk-test")
      client = described_class.build_from_env
      expect(client).to be_a(MerckTools::LLM::OpenAIClient)
    end
  end

  describe ".normalize_messages" do
    it "handles symbol keys" do
      msgs = [{ role: "user", content: "hi" }]
      result = described_class.normalize_messages(msgs)
      expect(result).to eq([{ role: "user", content: "hi" }])
    end

    it "handles string keys" do
      msgs = [{ "role" => "system", "content" => "be helpful" }]
      result = described_class.normalize_messages(msgs)
      expect(result).to eq([{ role: "system", content: "be helpful" }])
    end

    it "filters out empty messages" do
      msgs = [{ role: "", content: "hi" }, { role: "user", content: "" }, { role: "user", content: "hello" }]
      result = described_class.normalize_messages(msgs)
      expect(result).to eq([{ role: "user", content: "hello" }])
    end
  end
end

RSpec.describe MerckTools::LLM::MockClient do
  it "generates a mock response containing the user's question" do
    client = described_class.new
    result = client.generate(messages: [{ role: "user", content: "What is 2+2?" }])
    expect(result).to include("What is 2+2?")
    expect(result).to include("Mock AI")
  end
end

RSpec.describe MerckTools::LLM::MerckGwClient do
  let(:client) do
    described_class.new(
      api_root:    "https://gw.example.com/gpt/v2",
      api_version: "2025-04-14",
      model:       "gpt-4o",
      api_key:     "test-api-key",
      api_header:  "X-Merck-APIKey",
      timeout:     30
    )
  end

  it "sends request with correct headers and parses response" do
    stub_request(:post, /gw\.example\.com.*gpt-4o\/chat\/completions/)
      .with(headers: { "X-Merck-Apikey" => "test-api-key" })
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "Hello from GW" } }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    result = client.generate(messages: [{ role: "user", content: "hi" }])
    expect(result).to eq("Hello from GW")
  end

  it "tries alternate URL patterns on 404" do
    stub_request(:post, /gw\.example\.com.*\/gpt-4o\/chat\/completions/)
      .to_return(status: 404, body: "not found")
    stub_request(:post, /gw\.example\.com.*deployments\/gpt-4o\/chat\/completions/)
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "Found via deployments" } }] }.to_json
      )

    result = client.generate(messages: [{ role: "user", content: "hi" }])
    expect(result).to eq("Found via deployments")
  end
end

RSpec.describe MerckTools::LLM::OpenAIClient do
  let(:client) do
    described_class.new(
      api_key: "sk-test",
      api_base: "https://api.openai.com",
      model: "gpt-4o-mini",
      read_timeout: 10,
      open_timeout: 5
    )
  end

  it "sends request and parses response" do
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with(headers: { "Authorization" => "Bearer sk-test" })
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "Hello from OpenAI" } }] }.to_json
      )

    result = client.generate(messages: [{ role: "user", content: "hi" }])
    expect(result).to eq("Hello from OpenAI")
  end

  it "defaults to max_completion_tokens" do
    req = stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |request|
        body = JSON.parse(request.body)
        body.key?("max_completion_tokens") && !body.key?("max_tokens")
      }
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "ok" } }] }.to_json
      )

    client.generate(messages: [{ role: "user", content: "hi" }])
    expect(req).to have_been_requested
  end

  it "falls back to max_tokens when API rejects max_completion_tokens" do
    error_body = {
      error: {
        message: "Unsupported parameter: 'max_completion_tokens' is not supported with this model. Use 'max_tokens' instead.",
        type: "invalid_request_error",
        param: "max_completion_tokens",
        code: "unsupported_parameter"
      }
    }.to_json

    # First call rejected, second succeeds with max_tokens
    rejected = stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |r| JSON.parse(r.body).key?("max_completion_tokens") }
      .to_return(status: 400, body: error_body)

    retried = stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |r| JSON.parse(r.body).key?("max_tokens") && !JSON.parse(r.body).key?("max_completion_tokens") }
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "worked" } }] }.to_json
      )

    result = client.generate(messages: [{ role: "user", content: "hi" }])
    expect(result).to eq("worked")
    expect(rejected).to have_been_requested
    expect(retried).to have_been_requested
  end

  it "remembers the corrected param for subsequent calls" do
    error_body = {
      error: {
        message: "Unsupported parameter: 'max_completion_tokens' is not supported with this model. Use 'max_tokens' instead.",
        type: "invalid_request_error"
      }
    }.to_json

    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |r| JSON.parse(r.body).key?("max_completion_tokens") }
      .to_return(status: 400, body: error_body)

    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |r| JSON.parse(r.body).key?("max_tokens") }
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "ok" } }] }.to_json
      )

    client.generate(messages: [{ role: "user", content: "first" }])

    # Second call should go straight to max_tokens (no 400 needed)
    WebMock.reset!
    direct = stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .with { |r| JSON.parse(r.body).key?("max_tokens") && !JSON.parse(r.body).key?("max_completion_tokens") }
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "second" } }] }.to_json
      )

    result = client.generate(messages: [{ role: "user", content: "second" }])
    expect(result).to eq("second")
    expect(direct).to have_been_requested
  end
end
