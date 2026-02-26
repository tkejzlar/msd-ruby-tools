# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::Confluence::Client do
  let(:client) do
    described_class.new(
      base_url:  "https://wiki.example.com",
      username:  "svc-user",
      api_token: "svc-token"
    )
  end

  describe "authentication" do
    it "uses api_token when provided (Cloud)" do
      cloud_client = described_class.new(
        base_url: "https://wiki.example.com",
        username: "user@example.com",
        api_token: "cloud-api-token"
      )

      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/123/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("user@example.com:cloud-api-token")}" })
        .to_return(status: 200, body: { title: "Page", version: { number: 1 }, body: { storage: { value: "" } } }.to_json)

      cloud_client.read("123")
    end

    it "uses password when provided (Server/Data Center)" do
      server_client = described_class.new(
        base_url: "https://wiki.example.com",
        username: "svc-user",
        password: "my-password"
      )

      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/123/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("svc-user:my-password")}" })
        .to_return(status: 200, body: { title: "Page", version: { number: 1 }, body: { storage: { value: "" } } }.to_json)

      server_client.read("123")
    end

    it "prefers api_token over password when both are given" do
      client = described_class.new(
        base_url: "https://wiki.example.com",
        username: "user",
        api_token: "the-token",
        password: "the-password"
      )

      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/123/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("user:the-token")}" })
        .to_return(status: 200, body: { title: "Page", version: { number: 1 }, body: { storage: { value: "" } } }.to_json)

      client.read("123")
    end
  end

  describe "#read" do
    it "fetches a page with body and version" do
      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/12345/)
        .to_return(
          status: 200,
          body: {
            title: "My Page",
            version: { number: 5 },
            body: { storage: { value: "<p>Hello</p>" } }
          }.to_json
        )

      page = client.read("12345")
      expect(page["title"]).to eq("My Page")
      expect(page["version"]["number"]).to eq(5)
    end
  end

  describe "#search" do
    it "searches via CQL" do
      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/search/)
        .to_return(
          status: 200,
          body: { results: [{ id: "1", title: "Found page" }] }.to_json
        )

      results = client.search("type = page AND text ~ 'test'")
      expect(results["results"].first["title"]).to eq("Found page")
    end
  end

  describe "#write" do
    it "updates a page (incrementing version)" do
      # First: read to get current version
      stub_request(:get, /wiki\.example\.com\/rest\/api\/latest\/content\/12345/)
        .to_return(
          status: 200,
          body: { title: "My Page", version: { number: 5 }, body: { storage: { value: "<p>Old</p>" } } }.to_json
        )
      # Then: PUT with version 6
      stub_request(:put, /wiki\.example\.com\/rest\/api\/latest\/content\/12345/)
        .with { |req| JSON.parse(req.body)["version"]["number"] == 6 }
        .to_return(status: 200, body: { title: "My Page", version: { number: 6 } }.to_json)

      result = client.write("12345", "<p>New content</p>")
      expect(result["version"]["number"]).to eq(6)
    end
  end
end
