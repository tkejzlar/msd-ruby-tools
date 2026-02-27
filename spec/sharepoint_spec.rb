# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::SharePoint::Client do
  let(:base_url)  { "https://iapi.example.com/sharepoint/v1" }
  let(:api_key)   { "test-api-key" }
  let(:site_url)  { "https://collaboration.merck.com/sites/mysite" }
  let(:client_id) { "a6f748cd-fa2b-3d0a-9f61-c5f9d854174d" }
  let(:secret)    { "K74FViUJ3ko6pdpmFfUv0a9aS0e0ELjVcta2JqxxlcY=" }

  let(:client) do
    described_class.new(
      base_url:      base_url,
      api_key:       api_key,
      site_url:      site_url,
      client_id:     client_id,
      client_secret: secret,
      open_timeout:  2,
      read_timeout:  5
    )
  end

  let(:expected_headers) do
    {
      "X-Merck-APIKey" => api_key,
      "siteurl"        => site_url,
      "siteClientId"   => client_id,
      "siteSecretId"   => secret,
      "Content-Type"   => "application/json",
      "Accept"         => "application/json"
    }
  end

  # ── enabled? ─────────────────────────────────────────────────────

  describe "#enabled?" do
    it "returns true when all config is present" do
      expect(client.enabled?).to be true
    end

    it "returns false when base_url is blank" do
      c = described_class.new(base_url: "", api_key: api_key, site_url: site_url,
                              client_id: client_id, client_secret: secret)
      expect(c.enabled?).to be false
    end

    it "returns false when client_secret is blank" do
      c = described_class.new(base_url: base_url, api_key: api_key, site_url: site_url,
                              client_id: client_id, client_secret: "")
      expect(c.enabled?).to be false
    end
  end

  # ── lists ────────────────────────────────────────────────────────

  describe "#lists" do
    it "fetches lists collection" do
      body = { "_embedded" => { "listData" => [{ "Title" => "Badges" }] } }
      stub_request(:get, "#{base_url}/lists")
        .with(headers: expected_headers)
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.lists
      expect(result["_embedded"]["listData"].first["Title"]).to eq("Badges")
    end

    it "passes pagination query parameters" do
      stub_request(:get, "#{base_url}/lists?%24top=5&%24skip=10&%24select=Title,Id")
        .to_return(status: 200, body: { "_embedded" => { "listData" => [] } }.to_json)

      client.lists(top: 5, skip: 10, select: "Title,Id")
    end
  end

  # ── list_items ───────────────────────────────────────────────────

  describe "#list_items" do
    it "fetches items from a named list" do
      body = { "_embedded" => { "listData" => [{ "Id" => 1, "Title" => "Badge A" }] } }
      stub_request(:get, "#{base_url}/lists/Badges/items")
        .with(headers: expected_headers)
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.list_items("Badges")
      expect(result["_embedded"]["listData"].first["Title"]).to eq("Badge A")
    end

    it "passes pagination parameters" do
      stub_request(:get, "#{base_url}/lists/Badges/items?%24top=10&%24skip=20")
        .to_return(status: 200, body: { "_embedded" => { "listData" => [] } }.to_json)

      client.list_items("Badges", top: 10, skip: 20)
    end

    it "passes OData $filter parameter" do
      stub_request(:get, /lists\/Badges\/items/)
        .to_return(status: 200, body: { "_embedded" => { "listData" => [{ "Id" => 7 }] } }.to_json)

      result = client.list_items("Badges", filter: "SubmissionId eq '42'", top: 1)
      expect(result["_embedded"]["listData"].first["Id"]).to eq(7)
    end
  end

  # ── create_item ──────────────────────────────────────────────────

  describe "#create_item" do
    it "posts a new item and returns parsed response" do
      fields = { "Title" => "New Badge", "TeamName" => "Alpha" }
      response_body = { "_embedded" => { "listData" => { "Id" => 42, "Title" => "New Badge" } } }

      stub_request(:post, "#{base_url}/lists/Badges/items")
        .with(headers: expected_headers, body: fields.to_json)
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.create_item("Badges", fields)
      expect(result["_embedded"]["listData"]["Id"]).to eq(42)
    end

    it "raises Error on failure" do
      stub_request(:post, "#{base_url}/lists/Badges/items")
        .to_return(status: 500, body: { "error" => "original-api-error", "title" => "Original API error",
                                        "status" => 500, "detail" => "Something went wrong" }.to_json)

      expect { client.create_item("Badges", { "Title" => "X" }) }
        .to raise_error(MerckTools::SharePoint::Error, /500/)
    end
  end

  # ── update_item ──────────────────────────────────────────────────

  describe "#update_item" do
    it "puts updated fields for an item" do
      fields = { "Status" => "Awarded" }
      response_body = { "_links" => { "self" => { "href" => "/lists/Badges/items?$filter=Id eq 42" } },
                        "_embedded" => { "listData" => [] } }

      stub_request(:put, "#{base_url}/lists/Badges/items/42")
        .with(headers: expected_headers, body: fields.to_json)
        .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })

      result = client.update_item("Badges", 42, fields)
      expect(result["_links"]["self"]["href"]).to include("Badges")
    end
  end

  # ── delete_item ──────────────────────────────────────────────────

  describe "#delete_item" do
    it "deletes an item and returns true" do
      stub_request(:delete, "#{base_url}/lists/Badges/items/42")
        .with(headers: expected_headers)
        .to_return(status: 200, body: "")

      expect(client.delete_item("Badges", 42)).to be true
    end

    it "raises Error on failure" do
      stub_request(:delete, "#{base_url}/lists/Badges/items/99")
        .to_return(status: 504, body: { "error" => "gateway-timeout", "title" => "Gateway Timeout",
                                        "status" => 504, "detail" => "timeout of 55000ms exceeded" }.to_json)

      expect { client.delete_item("Badges", 99) }
        .to raise_error(MerckTools::SharePoint::Error, /504/)
    end
  end

  # ── ENV-based construction ───────────────────────────────────────

  describe "ENV-based construction" do
    it "reads config from ENV vars" do
      stub_env(
        "SP_BASE_URL"      => base_url,
        "SP_API_KEY"       => api_key,
        "SP_SITE_URL"      => site_url,
        "SP_CLIENT_ID"     => client_id,
        "SP_CLIENT_SECRET" => secret
      )

      env_client = described_class.new
      expect(env_client.enabled?).to be true
    end

    it "is disabled when ENV vars are missing" do
      env_client = described_class.new
      expect(env_client.enabled?).to be false
    end
  end

  # ── URL encoding ─────────────────────────────────────────────────

  describe "URL encoding" do
    it "encodes list names with special characters" do
      stub_request(:get, "#{base_url}/lists/My+List/items")
        .to_return(status: 200, body: { "_embedded" => { "listData" => [] } }.to_json)

      client.list_items("My List")
    end
  end
end
