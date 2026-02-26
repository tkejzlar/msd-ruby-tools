# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::MSGraph::Client do
  let(:client) do
    described_class.new(
      base: "https://graph.example.com/v1.0",
      api_key: "graph-key",
      upn_domain: "merck.com",
      open_timeout: 2,
      read_timeout: 5
    )
  end

  describe "#user" do
    it "fetches user profile" do
      stub_request(:get, "https://graph.example.com/v1.0/users/jdoe%40merck.com")
        .with(headers: { "X-Merck-APIKey" => "graph-key" })
        .to_return(
          status: 200,
          body: { displayName: "John Doe", mail: "jdoe@merck.com" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      user = client.user("jdoe@merck.com")
      expect(user["displayName"]).to eq("John Doe")
    end
  end

  describe "#user_photo_raw" do
    it "fetches photo bytes" do
      stub_request(:get, "https://graph.example.com/v1.0/users/jdoe%40merck.com/photo/%24value")
        .to_return(status: 200, body: "PHOTO_BYTES", headers: { "Content-Type" => "image/jpeg" })

      result = client.user_photo_raw("jdoe@merck.com")
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("PHOTO_BYTES")
      expect(result[:content_type]).to eq("image/jpeg")
    end
  end

  describe "#user_photo" do
    it "tries multiple identifiers and returns first success" do
      profile = { "email" => "jdoe@merck.com", "isid" => "jdoe" }

      stub_request(:get, /graph\.example\.com.*jdoe.*photo/)
        .to_return(status: 200, body: "IMG", headers: { "Content-Type" => "image/png" })

      result = client.user_photo(profile)
      expect(result[:status]).to eq(200)
      expect(result[:body]).to eq("IMG")
    end
  end
end
