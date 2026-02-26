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
end
