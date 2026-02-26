# frozen_string_literal: true

require "rest-client"
require "json"
require "base64"

module MerckTools
  module Confluence
    class Error < StandardError; end

    # Confluence REST API client (v1 content API).
    #
    # ENV vars:
    #   CONFLUENCE_BASE_URL          – e.g. https://share.merck.com
    #   CONFLUENCE_USER              – service account user (fallback: JIRA_EMAIL, predictify_user)
    #   CONFLUENCE_API_TOKEN         – service account token (fallback: JIRA_API_TOKEN, predictify_password)
    #   CONFLUENCE_DEFAULT_CONFIG_PAGE – default page ID for config lookups
    #
    class Client
      attr_reader :base_url

      def initialize(
        base_url:  ENV.fetch("CONFLUENCE_BASE_URL") { ENV.fetch("CONFLUENCE_REST_URL", "https://share.merck.com") },
        username:  ENV.fetch("CONFLUENCE_USER")      { ENV.fetch("JIRA_EMAIL") { ENV["predictify_user"] } },
        api_token: ENV.fetch("CONFLUENCE_API_TOKEN") { ENV.fetch("JIRA_API_TOKEN") { ENV["predictify_password"] } }
      )
        @base_url  = base_url.to_s.chomp("/")
        @username  = username.to_s
        @api_token = api_token.to_s
      end

      # Read a page's storage-format body and version info.
      def read(page_id)
        get("/rest/api/latest/content/#{page_id}", params: { expand: "version,body.storage" })
      end

      # Update a page's content (auto-increments version).
      def write(page_id, content)
        page = read(page_id)
        raise Error, "Cannot read page #{page_id}" unless page

        version = page.dig("version", "number").to_i
        payload = {
          "version" => { "number" => version + 1, "minorEdit" => true },
          "type"    => "page",
          "title"   => page["title"],
          "body"    => {
            "storage" => { "value" => content, "representation" => "storage" }
          }
        }
        put("/rest/api/latest/content/#{page_id}", payload)
      end

      # Search via CQL.
      def search(cql)
        get("/rest/api/latest/content/search", params: { cql: cql })
      end

      # List attachments for a page.
      def attachments(page_id)
        get("/rest/api/latest/content/#{page_id}/child/attachment", params: { expand: "version" })
      end

      # Download a specific attachment by filename.
      def download_attachment(page_id, filename)
        list = attachments(page_id)
        results = list && list["results"] || []
        att = results.find { |a| a["title"] == filename }
        return nil unless att

        url = "#{@base_url}#{att['_links']['download']}"
        resp = RestClient::Request.execute(
          method: :get, url: url,
          headers: { Authorization: auth_header, Accept: "*/*" },
          timeout: 120
        )
        resp.body
      end

      private

      def auth_header
        "Basic #{Base64.strict_encode64("#{@username}:#{@api_token}")}"
      end

      def get(path, params: {})
        url = "#{@base_url}#{path}"
        resp = RestClient::Request.execute(
          method: :get, url: url,
          headers: { Authorization: auth_header, Accept: "application/json", params: params },
          timeout: 300
        )
        JSON.parse(resp.body)
      rescue RestClient::ExceptionWithResponse => e
        raise Error, "Confluence GET #{path} failed: #{e.response&.code} #{e.response&.body&.to_s&.slice(0, 300)}"
      end

      def put(path, payload)
        url = "#{@base_url}#{path}"
        resp = RestClient::Request.execute(
          method: :put, url: url,
          headers: { Authorization: auth_header, content_type: :json },
          payload: payload.to_json,
          timeout: 120
        )
        JSON.parse(resp.body)
      rescue RestClient::ExceptionWithResponse => e
        raise Error, "Confluence PUT #{path} failed: #{e.response&.code} #{e.response&.body&.to_s&.slice(0, 300)}"
      end
    end
  end
end
