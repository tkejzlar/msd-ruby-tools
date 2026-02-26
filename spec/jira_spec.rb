# frozen_string_literal: true

require "spec_helper"

RSpec.describe MerckTools::Jira::Client do
  let(:client) do
    described_class.new(
      base_url:  "https://jira.example.com",
      username:  "svc-user",
      api_token: "svc-token",
      pagination: 50,
      log_level: "ERROR"
    )
  end

  describe "authentication" do
    it "uses api_token when provided (Cloud)" do
      cloud_client = described_class.new(
        base_url: "https://jira.example.com",
        username: "user@example.com",
        api_token: "cloud-api-token",
        log_level: "ERROR"
      )

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("user@example.com:cloud-api-token")}" })
        .to_return(status: 200, body: { issues: [], total: 0 }.to_json)

      cloud_client.search("project = PROJ")
    end

    it "uses password when provided (Server/Data Center)" do
      server_client = described_class.new(
        base_url: "https://jira.example.com",
        username: "svc-user",
        password: "my-password",
        log_level: "ERROR"
      )

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("svc-user:my-password")}" })
        .to_return(status: 200, body: { issues: [], total: 0 }.to_json)

      server_client.search("project = PROJ")
    end

    it "prefers api_token over password when both are given" do
      client = described_class.new(
        base_url: "https://jira.example.com",
        username: "user",
        api_token: "the-token",
        password: "the-password",
        log_level: "ERROR"
      )

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("user:the-token")}" })
        .to_return(status: 200, body: { issues: [], total: 0 }.to_json)

      client.search("project = PROJ")
    end

    it "falls back to JIRA_PASSWORD env var when neither api_token nor password is given" do
      stub_env("JIRA_API_TOKEN" => nil, "JIRA_PASSWORD" => "env-password", "predictify_password" => nil)

      env_client = described_class.new(
        base_url: "https://jira.example.com",
        username: "svc-user",
        log_level: "ERROR"
      )

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("svc-user:env-password")}" })
        .to_return(status: 200, body: { issues: [], total: 0 }.to_json)

      env_client.search("project = PROJ")
    end

    it "falls back to JIRA_USERNAME env var for username" do
      stub_env("JIRA_EMAIL" => nil, "JIRA_USERNAME" => "server-user", "predictify_user" => nil)

      env_client = described_class.new(
        base_url: "https://jira.example.com",
        api_token: "tok",
        log_level: "ERROR"
      )

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .with(headers: { "Authorization" => "Basic #{Base64.strict_encode64("server-user:tok")}" })
        .to_return(status: 200, body: { issues: [], total: 0 }.to_json)

      env_client.search("project = PROJ")
    end
  end

  describe "#search" do
    it "fetches issues via JQL" do
      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .to_return(
          status: 200,
          body: { issues: [{ key: "PROJ-1", fields: { summary: "Test" } }], total: 1 }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      issues = client.search("project = PROJ")
      expect(issues.length).to eq(1)
      expect(issues.first["key"]).to eq("PROJ-1")
    end

    it "handles pagination" do
      page1 = { issues: Array.new(50) { |i| { key: "P-#{i}", fields: {} } }, total: 75 }.to_json
      page2 = { issues: Array.new(25) { |i| { key: "P-#{50+i}", fields: {} } }, total: 75 }.to_json

      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/search/)
        .to_return(
          { status: 200, body: page1 },
          { status: 200, body: page2 }
        )

      issues = client.search("project = PROJ")
      expect(issues.length).to eq(75)
    end
  end

  describe "#issue" do
    it "fetches a single issue" do
      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/issue\/PROJ-1/)
        .to_return(
          status: 200,
          body: { key: "PROJ-1", fields: { summary: "A bug" } }.to_json
        )

      result = client.issue("PROJ-1")
      expect(result["key"]).to eq("PROJ-1")
    end
  end

  describe "#project_versions" do
    it "returns versions array" do
      stub_request(:get, /jira\.example\.com\/rest\/api\/latest\/project\/PROJ\/versions/)
        .to_return(
          status: 200,
          body: [{ id: "1", name: "v1.0", released: true }].to_json
        )

      versions = client.project_versions("PROJ")
      expect(versions.first["name"]).to eq("v1.0")
    end
  end

  describe "#create_issue" do
    it "creates an issue" do
      stub_request(:post, /jira\.example\.com\/rest\/api\/latest\/issue/)
        .to_return(
          status: 201,
          body: { key: "PROJ-99" }.to_json
        )

      result = client.create_issue({ fields: { summary: "New issue", project: { key: "PROJ" } } })
      expect(result["key"]).to eq("PROJ-99")
    end
  end
end
