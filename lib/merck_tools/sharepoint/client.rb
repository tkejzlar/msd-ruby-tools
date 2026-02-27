# frozen_string_literal: true

require "uri"
require "net/http"
require "json"

module MerckTools
  module SharePoint
    class Error < StandardError; end

    # SharePoint Online API client (via Merck iAPI proxy).
    #
    # Wraps the SharePoint REST API proxy that uses the SharePoint app
    # permission model.  Provides generic CRUD for lists and list items.
    #
    # ENV vars:
    #   SP_BASE_URL       – proxy base URL (e.g. https://iapi.merck.com/sharepoint/v1)
    #   SP_API_KEY        – X-Merck-APIKey value
    #   SP_SITE_URL       – target SharePoint site URL (sent as siteurl header)
    #   SP_CLIENT_ID      – SharePoint app client ID (sent as siteClientId header)
    #   SP_CLIENT_SECRET  – SharePoint app client secret (sent as siteSecretId header)
    #   SP_OPEN_TIMEOUT   – connect timeout seconds (default: 5)
    #   SP_READ_TIMEOUT   – read timeout seconds (default: 30)
    #
    class Client
      def initialize(
        base_url:      ENV.fetch("SP_BASE_URL", ""),
        api_key:       ENV.fetch("SP_API_KEY", ""),
        site_url:      ENV.fetch("SP_SITE_URL", ""),
        client_id:     ENV.fetch("SP_CLIENT_ID", ""),
        client_secret: ENV.fetch("SP_CLIENT_SECRET", ""),
        open_timeout:  Integer(ENV.fetch("SP_OPEN_TIMEOUT", "5")),
        read_timeout:  Integer(ENV.fetch("SP_READ_TIMEOUT", "30"))
      )
        @base_url      = base_url.to_s.chomp("/")
        @api_key       = api_key.to_s
        @site_url      = site_url.to_s
        @client_id     = client_id.to_s
        @client_secret = client_secret.to_s
        @open_timeout  = open_timeout
        @read_timeout  = read_timeout
      end

      # True when all required configuration is present.
      def enabled?
        !@base_url.empty? && !@api_key.empty? &&
          !@site_url.empty? && !@client_id.empty? && !@client_secret.empty?
      end

      # ── Lists ──────────────────────────────────────────────────────

      # Fetch the lists collection.
      #
      # @param top    [Integer, nil] pagination page size
      # @param skip   [Integer, nil] number of items to skip
      # @param select [String, nil]  comma-separated field names
      # @return [Hash] parsed response body
      def lists(top: nil, skip: nil, select: nil)
        params = build_query(top: top, skip: skip, select: select)
        api_get("/lists", params: params)
      end

      # ── List Items ─────────────────────────────────────────────────

      # Fetch items from a list.
      #
      # @param list_name [String]       list name / title
      # @param top       [Integer, nil] pagination page size
      # @param skip      [Integer, nil] number of items to skip
      # @param select    [String, nil]  comma-separated field names
      # @param filter    [String, nil]  OData $filter expression
      # @return [Hash] parsed response body
      def list_items(list_name, top: nil, skip: nil, select: nil, filter: nil)
        params = build_query(top: top, skip: skip, select: select, filter: filter)
        api_get("/lists/#{encode(list_name)}/items", params: params)
      end

      # Create a new item in a list.
      #
      # @param list_name [String] list name / title
      # @param fields    [Hash]   field values for the new item
      # @return [Hash] parsed response body (created item)
      def create_item(list_name, fields)
        api_post("/lists/#{encode(list_name)}/items", fields)
      end

      # Update an existing list item.
      #
      # @param list_name [String]  list name / title
      # @param item_id   [Integer] item ID
      # @param fields    [Hash]    field values to update
      # @return [Hash] parsed response body
      def update_item(list_name, item_id, fields)
        api_put("/lists/#{encode(list_name)}/items/#{item_id}", fields)
      end

      # Delete a list item.
      #
      # @param list_name [String]  list name / title
      # @param item_id   [Integer] item ID
      # @return [true] on success
      def delete_item(list_name, item_id)
        api_delete("/lists/#{encode(list_name)}/items/#{item_id}")
        true
      end

      private

      def encode(value)
        URI.encode_www_form_component(value.to_s)
      end

      def build_query(top: nil, skip: nil, select: nil, filter: nil)
        params = {}
        params["$top"]    = top.to_i    if top
        params["$skip"]   = skip.to_i   if skip
        params["$select"] = select.to_s if select
        params["$filter"] = filter.to_s if filter
        params
      end

      # ── HTTP helpers ───────────────────────────────────────────────

      def api_get(path, params: {})
        uri = build_uri(path, params)
        request = Net::HTTP::Get.new(uri)
        apply_headers(request)
        execute(uri, request)
      end

      def api_post(path, body)
        uri = build_uri(path)
        request = Net::HTTP::Post.new(uri)
        apply_headers(request)
        request.body = body.to_json
        execute(uri, request)
      end

      def api_put(path, body)
        uri = build_uri(path)
        request = Net::HTTP::Put.new(uri)
        apply_headers(request)
        request.body = body.to_json
        execute(uri, request)
      end

      def api_delete(path)
        uri = build_uri(path)
        request = Net::HTTP::Delete.new(uri)
        apply_headers(request)
        execute(uri, request)
      end

      def build_uri(path, params = {})
        uri = URI.parse("#{@base_url}#{path}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def apply_headers(request)
        request["Content-Type"]   = "application/json"
        request["Accept"]         = "application/json"
        request["X-Merck-APIKey"] = @api_key
        request["siteurl"]        = @site_url
        request["siteClientId"]   = @client_id
        request["siteSecretId"]   = @client_secret
      end

      def execute(uri, request)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "SharePoint API #{request.method} #{uri.path} " \
                       "returned #{response.code}: #{response.body.to_s[0..500]}"
        end

        body = response.body.to_s.strip
        body.empty? ? {} : JSON.parse(body)
      rescue JSON::ParserError => e
        raise Error, "SharePoint API response parse error: #{e.message}"
      end
    end
  end
end
