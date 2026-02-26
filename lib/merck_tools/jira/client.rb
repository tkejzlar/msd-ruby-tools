# frozen_string_literal: true

require "rest-client"
require "json"
require "base64"
require "logger"

module MerckTools
  module Jira
    class Error < StandardError; end

    # Jira REST API client.
    #
    # Supports both service-account queries and per-user actions (vote, comment).
    #
    # ENV vars:
    #   JIRA_BASE_URL       – e.g. https://issues.merck.com
    #   JIRA_EMAIL          – service account email/username
    #   JIRA_API_TOKEN      – service account API token / password
    #   JIRA_PAGINATION     – max results per request (default: 500)
    #   JIRA_LOG_LEVEL      – DEBUG / INFO / WARN / ERROR
    #
    class Client
      DEFAULT_FIELDS = %w[
        summary status description assignee labels duedate fixVersions
        priority created updated issuetype project components comment votes
      ].freeze

      attr_reader :base_url

      def initialize(
        base_url:   ENV.fetch("JIRA_BASE_URL") { ENV.fetch("JIRA_REST_URL", "https://issues.merck.com") },
        username:   ENV.fetch("JIRA_EMAIL")     { ENV["predictify_user"] },
        api_token:  ENV.fetch("JIRA_API_TOKEN") { ENV["predictify_password"] },
        pagination: Integer(ENV.fetch("JIRA_PAGINATION", "500")),
        log_level:  ENV.fetch("JIRA_LOG_LEVEL", "WARN")
      )
        @base_url   = base_url.to_s.chomp("/")
        @username   = username.to_s
        @api_token  = api_token.to_s
        @pagination = pagination
        @logger     = Logger.new($stdout)
        @logger.level = Logger.const_get(log_level.upcase) rescue Logger::WARN
      end

      # ── Search ────────────────────────────────────────────────────

      # Run a JQL search, handling pagination automatically.
      # Returns an Array of issue hashes.
      def search(jql, fields: nil, expand: nil, max_results: nil)
        all_fields = (Array(DEFAULT_FIELDS) | Array(fields)).uniq
        limit      = max_results || @pagination
        start_at   = 0
        issues     = []

        loop do
          params = {
            jql:        jql,
            fields:     all_fields.join(","),
            maxResults: [limit, @pagination].min,
            startAt:    start_at
          }
          params[:expand] = Array(expand).join(",") if expand

          data = get("/rest/api/latest/search", params: params)
          break unless data.is_a?(Hash) && data["issues"]

          issues.concat(data["issues"])
          total = data["total"].to_i
          break if issues.length >= total || data["issues"].empty?
          break if max_results && issues.length >= max_results

          start_at += data["issues"].length
        end

        max_results ? issues.first(max_results) : issues
      end

      # ── Single issue ──────────────────────────────────────────────

      def issue(key, fields: nil, expand: "renderedFields")
        all_fields = (Array(DEFAULT_FIELDS) | Array(fields)).uniq
        params = { fields: all_fields.join(",") }
        params[:expand] = expand if expand
        get("/rest/api/latest/issue/#{key}", params: params)
      end

      # ── Versions ──────────────────────────────────────────────────

      def project_versions(project_key)
        get("/rest/api/latest/project/#{project_key}/versions") || []
      end

      def project(project_key, include_versions: false)
        data = get("/rest/api/latest/project/#{project_key}")
        if include_versions && data
          data["versions"] = project_versions(project_key)
        end
        data
      end

      # ── Sprints ───────────────────────────────────────────────────

      def sprints(board_id, state: nil)
        all = []
        start_at = 0
        loop do
          params = { maxResults: 50, startAt: start_at }
          params[:state] = state if state
          data = get("/rest/agile/latest/board/#{board_id}/sprint", params: params)
          values = data && data["values"] || []
          break if values.empty?
          all.concat(values)
          start_at += values.length
        end
        all
      end

      # ── Issue votes & comments ────────────────────────────────────

      def votes(issue_key)
        resp = get("/rest/api/latest/issue/#{issue_key}/votes")
        resp ? resp["votes"].to_i : 0
      end

      def comments(issue_key)
        resp = get("/rest/api/latest/issue/#{issue_key}/comment", params: { maxResults: 100 })
        resp ? resp["comments"] || [] : []
      end

      # ── Create issue ──────────────────────────────────────────────

      def create_issue(payload, bulk: false)
        path = bulk ? "/rest/api/latest/issue/bulk" : "/rest/api/latest/issue"
        post(path, payload)
      end

      # ── Per-user actions (vote / comment with user's own credentials) ──

      def vote_as_user(issue_key, username:, token:)
        post_as("/rest/api/latest/issue/#{issue_key}/votes", nil, username: username, token: token)
      end

      def comment_as_user(issue_key, body:, username:, token:)
        post_as("/rest/api/latest/issue/#{issue_key}/comment", { body: body }, username: username, token: token)
      end

      private

      def auth_header(user = @username, pass = @api_token)
        "Basic #{Base64.strict_encode64("#{user}:#{pass}")}"
      end

      def get(path, params: {})
        url = "#{@base_url}#{path}"
        @logger.debug("[JIRA][GET] #{url}")
        resp = RestClient::Request.execute(
          method:  :get,
          url:     url,
          headers: {
            Authorization: auth_header,
            Accept: "application/json",
            params: params
          },
          timeout: 300
        )
        JSON.parse(resp.body)
      rescue RestClient::ExceptionWithResponse => e
        @logger.error("[JIRA][GET] #{url} #{e.response&.code}: #{e.response&.body&.to_s&.slice(0, 300)}")
        nil
      rescue => e
        @logger.error("[JIRA][GET] #{url} #{e.class}: #{e.message}")
        nil
      end

      def post(path, payload)
        url = "#{@base_url}#{path}"
        @logger.debug("[JIRA][POST] #{url}")
        resp = RestClient::Request.execute(
          method:  :post,
          url:     url,
          headers: {
            Authorization: auth_header,
            Accept: "application/json",
            content_type: :json
          },
          payload: payload.to_json,
          timeout: 120
        )
        JSON.parse(resp.body)
      rescue RestClient::ExceptionWithResponse => e
        @logger.error("[JIRA][POST] #{url} #{e.response&.code}: #{e.response&.body&.to_s&.slice(0, 300)}")
        raise Error, "Jira POST failed: #{e.response&.code}"
      end

      def post_as(path, payload, username:, token:)
        url = "#{@base_url}#{path}"
        headers = {
          Authorization: auth_header(username, token),
          Accept: "application/json",
          content_type: :json
        }
        args = { method: :post, url: url, headers: headers, timeout: 60 }
        args[:payload] = payload.to_json if payload
        RestClient::Request.execute(**args)
        true
      rescue RestClient::ExceptionWithResponse => e
        @logger.error("[JIRA][POST_AS] #{url} #{e.response&.code}")
        false
      rescue => e
        @logger.error("[JIRA][POST_AS] #{url} #{e.class}: #{e.message}")
        false
      end
    end
  end
end
