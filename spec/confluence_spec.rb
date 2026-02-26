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
