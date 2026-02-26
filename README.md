# MerckTools

Shared Ruby client library for Merck internal APIs. Provides a single gem with
modules for LLM (AI gateway, OpenAI, Anthropic, Gemini), OAuth SSO, Jira,
Confluence, and Microsoft Graph — all framework-agnostic and configurable via
environment variables.

## Installation

Add to your `Gemfile`:

```ruby
gem "merck_tools", git: "https://github.com/tkejzlar/msd-ruby-tools.git"
```

Then run:

```bash
bundle install
```

**Requires Ruby >= 3.0.**

## Quick start

```ruby
require "merck_tools"

# LLM — auto-selects provider from ENV
client = MerckTools::LLM.build_from_env
response = client.generate(messages: [{ role: "user", content: "Summarise this document…" }])

# Jira
jira = MerckTools::Jira::Client.new
issues = jira.search('project = MYPROJ AND status = "In Progress"')

# Confluence
wiki = MerckTools::Confluence::Client.new
page = wiki.read("123456")

# OAuth
oauth = MerckTools::Auth::OAuthClient.new
url   = oauth.authorize_url(state: SecureRandom.hex)

# MS Graph
graph = MerckTools::MSGraph::Client.new
user  = graph.user("jdoe@merck.com")
```

---

## Modules

### LLM (`MerckTools::LLM`)

Factory-based access to multiple AI providers. Every client responds to:

```ruby
client.generate(messages:, temperature: 0.2, max_tokens: 900, json: false)  #=> String
client.stream(messages:, temperature: 0.2, max_tokens: 900, json: false) { |chunk| ... }
```

#### Provider selection

```ruby
# Automatic — reads AI_PROVIDER / LLM_PROVIDER env var
client = MerckTools::LLM.build_from_env

# Explicit override
client = MerckTools::LLM.build_from_env(provider: "openai")
```

| `AI_PROVIDER` value | Client class | Notes |
|---|---|---|
| `merck_gw` / `gw` | `MerckGwClient` | Merck Azure-OpenAI gateway |
| `openai` | `OpenAIClient` | Direct OpenAI API (net/http) |
| `anthropic` | `RubyLLMClient` | Via `ruby_llm` gem |
| `ruby_llm` / `ruby-llm` | `RubyLLMClient` | Auto-detects provider from model name |
| `mock` / unset | `MockClient` | Returns placeholder text |

#### Message format

Messages are arrays of hashes with `role` and `content` keys (string or symbol):

```ruby
messages = [
  { role: "system", content: "You are a helpful assistant." },
  { role: "user",   content: "What is 2 + 2?" }
]
```

#### Environment variables — Merck GW

| Variable | Default | Description |
|---|---|---|
| `GW_API_ROOT` | `https://iapi-test.merck.com/gpt/v2` | Gateway base URL |
| `GW_API_VERSION` | `2025-04-14` | `api-version` query param |
| `GW_MODEL` | `gpt-4o-mini` | Deployment / model name |
| `MERCK_GW_API_KEY` | — **required** | API key |
| `GW_API_HEADER` | `X-Merck-APIKey` | Header name for API key |
| `AI_HTTP_TIMEOUT` | `300` | Read timeout (seconds) |

Legacy fallbacks: `MERCK_API_ROOT`, `MERCK_API_VERSION`, `MERCK_DEPLOYMENT`,
`X_MERCK_APIKEY`, `MERCK_API_KEY`, `MERCK_API_HEADER`, `OPENAI_MODEL`.

#### Environment variables — OpenAI

| Variable | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | — **required** | OpenAI API key |
| `OPENAI_API_BASE` | `https://api.openai.com` | Base URL |
| `OPENAI_MODEL` | `gpt-4o-mini` | Model identifier |
| `HTTP_READ_TIMEOUT` | `600` | Read timeout (seconds) |
| `HTTP_OPEN_TIMEOUT` | `30` | Connection timeout (seconds) |

#### Environment variables — RubyLLM (multi-provider)

Requires `gem "ruby_llm"` in your Gemfile (not bundled with this gem).

| Variable | Default | Description |
|---|---|---|
| `OPENAI_API_KEY` | — | Required for OpenAI provider |
| `ANTHROPIC_API_KEY` | — | Required for Anthropic provider |
| `GEMINI_API_KEY` | — | Required for Gemini provider |
| `OPENAI_MODEL` | `gpt-4o-mini` | OpenAI model |
| `ANTHROPIC_MODEL` | `claude-sonnet-4-5-20250514` | Anthropic model |
| `GEMINI_MODEL` | `gemini-2.0-flash` | Gemini model |
| `AI_MODEL` | `gpt-4o-mini` | Fallback model (also used to auto-detect provider) |

---

### Auth (`MerckTools::Auth`)

#### OAuthClient

OAuth 2.0 authorization-code flow for Merck SSO.

```ruby
oauth = MerckTools::Auth::OAuthClient.new

# 1. Redirect user to SSO
redirect_to oauth.authorize_url(state: session[:csrf])

# 2. Exchange code for tokens (in callback)
result = oauth.exchange_code(code: params[:code])
# result => { status: 200, json: { "access_token" => "...", "refresh_token" => "..." } }

# 3. Fetch user profile
profile = oauth.userinfo(access_token: result[:json]["access_token"])

# 4. Refresh when expired
new_tokens = oauth.refresh_token(refresh_token: result[:json]["refresh_token"])

# 5. Validate a token
info = oauth.introspect(token: access_token)
# info[:json]["active"] => true/false
```

| Variable | Default | Description |
|---|---|---|
| `OAUTH_BASE` | `https://iapi-test.merck.com/authentication-service/v2` | OAuth server base URL |
| `OAUTH_CLIENT_ID` | — **required** | Client ID |
| `OAUTH_CLIENT_SECRET` | — **required** | Client secret (raw or pre-encoded Base64) |
| `OAUTH_REDIRECT_URI` | — | Registered callback URL |
| `OAUTH_SCOPE` | `default` | OAuth scope |
| `OAUTH_LOGIN_METHOD` | `sso` | Login method parameter |

Legacy fallbacks: `OAUTH_HOST`, `OAUTH_KEY`, `OAUTH_SECRET`.

#### DevAuth

Development-mode authentication bypass. Reads user identity from HTTP headers
instead of hitting the real OAuth provider.

```ruby
# In a Rack middleware or controller:
if MerckTools::Auth::DevAuth.enabled?
  profile = MerckTools::Auth::DevAuth.profile_from_headers(request.env)
  # => { "email" => "jdoe@merck.com", "name" => "John Doe", "roles" => ["admin"], ... }
end
```

| Variable | Default | Description |
|---|---|---|
| `DEV_AUTH` | — | Set to `"1"` to enable |
| `DEV_AUTH_PASSPHRASE` | — | Optional passphrase guard |

**Headers** (Rack or direct style):

| Header | Purpose |
|---|---|
| `X-Dev-User` | Email address (**required**) |
| `X-Dev-Name` | Full name (defaults to email username) |
| `X-Dev-Roles` | Comma-separated role list |
| `X-Dev-Isid` | ISID identifier |

> **Warning:** DevAuth only activates when `DEV_AUTH=1` and environment is
> `nil` or `"development"`. Never enable in production.

---

### Jira (`MerckTools::Jira`)

REST API v3 client with automatic pagination.

```ruby
jira = MerckTools::Jira::Client.new

# Search with JQL (auto-paginates)
issues = jira.search('project = MYPROJ ORDER BY created DESC', max_results: 100)

# Single issue
issue = jira.issue("MYPROJ-42")

# Project info
project = jira.project("MYPROJ", include_versions: true)

# Sprints from an agile board
sprints = jira.sprints(42, state: "active")

# Votes and comments
count    = jira.votes("MYPROJ-42")
comments = jira.comments("MYPROJ-42")

# Create an issue
jira.create_issue(fields: { summary: "Bug report", project: { key: "MYPROJ" }, issuetype: { name: "Bug" } })

# Per-user actions (vote/comment with the user's own credentials)
jira.vote_as_user("MYPROJ-42", username: "jdoe", token: user_token)
jira.comment_as_user("MYPROJ-42", body: "Looks good!", username: "jdoe", token: user_token)
```

| Variable | Default | Description |
|---|---|---|
| `JIRA_BASE_URL` | `https://issues.merck.com` | Jira server URL |
| `JIRA_EMAIL` | — **required** | Service account email/username |
| `JIRA_API_TOKEN` | — **required** | Service account API token |
| `JIRA_PAGINATION` | `500` | Max results per API request |
| `JIRA_LOG_LEVEL` | `WARN` | Log level: DEBUG, INFO, WARN, ERROR |

Legacy fallbacks: `JIRA_REST_URL`, `predictify_user`, `predictify_password`.

---

### Confluence (`MerckTools::Confluence`)

REST API v1 content client.

```ruby
wiki = MerckTools::Confluence::Client.new

# Read a page (storage-format HTML + version)
page = wiki.read("123456")
html = page.dig("body", "storage", "value")

# Update a page (auto-increments version)
wiki.write("123456", "<p>Updated content</p>")

# Search via CQL
results = wiki.search("type = page AND space = MYSPACE AND text ~ 'deployment'")

# Attachments
list = wiki.attachments("123456")
bytes = wiki.download_attachment("123456", "report.xlsx")
```

| Variable | Default | Description |
|---|---|---|
| `CONFLUENCE_BASE_URL` | `https://share.merck.com` | Confluence server URL |
| `CONFLUENCE_USER` | — | Service account user |
| `CONFLUENCE_API_TOKEN` | — | Service account token |
| `CONFLUENCE_LOG_LEVEL` | `WARN` | Log level: DEBUG, INFO, WARN, ERROR |

Falls back to `JIRA_EMAIL` / `JIRA_API_TOKEN` if Confluence-specific vars are
not set. Legacy fallbacks: `CONFLUENCE_REST_URL`, `predictify_user`,
`predictify_password`.

---

### MS Graph (`MerckTools::MSGraph`)

Microsoft Graph API client via Merck API proxy.

```ruby
graph = MerckTools::MSGraph::Client.new

# Fetch user profile
user = graph.user("jdoe@merck.com")

# Fetch user photo (tries email, isid@domain, isid, UPN)
photo = graph.user_photo({ "email" => "jdoe@merck.com", "isid" => "jdoe" })
# photo => { status: 200, body: <bytes>, content_type: "image/jpeg" }

# Direct reports
reports = graph.direct_reports("jdoe@merck.com")
```

| Variable | Default | Description |
|---|---|---|
| `MS_GRAPH_BASE` | — | Graph API base URL (e.g. `https://iapi.merck.com/microsoft-graph/v1.0`) |
| `MS_GRAPH_API_KEY` | — | `X-Merck-APIKey` value |
| `MS_GRAPH_UPN_DOMAIN` | `merck.com` | Default domain for ISID-based lookups |
| `MS_GRAPH_OPEN_TIMEOUT` | `2` | Connection timeout (seconds) |
| `MS_GRAPH_READ_TIMEOUT` | `5` | Read timeout (seconds) |

Legacy fallbacks: `GRAPH_HOST`, `GRAPH_KEY`.

---

## Environment variables reference

Below is every env var the gem reads, grouped by module. **Bold** = required for
that module to function.

<details>
<summary>Full table (click to expand)</summary>

### LLM provider selection

| Variable | Purpose |
|---|---|
| `AI_PROVIDER` / `LLM_PROVIDER` | Provider name: `merck_gw`, `openai`, `anthropic`, `ruby_llm`, `mock` |
| `AI_MODEL` | Fallback model name; also used to auto-detect ruby_llm provider |

### Merck GW LLM

| Variable | Purpose |
|---|---|
| **`MERCK_GW_API_KEY`** | Gateway API key |
| `GW_API_ROOT` | Base URL |
| `GW_API_VERSION` | API version param |
| `GW_MODEL` | Deployment name |
| `GW_API_HEADER` | Auth header name |
| `AI_HTTP_TIMEOUT` | Read timeout |

### OpenAI LLM

| Variable | Purpose |
|---|---|
| **`OPENAI_API_KEY`** | OpenAI API key |
| `OPENAI_API_BASE` | Base URL |
| `OPENAI_MODEL` | Model name |
| `HTTP_READ_TIMEOUT` | Read timeout |
| `HTTP_OPEN_TIMEOUT` | Connect timeout |

### RubyLLM

| Variable | Purpose |
|---|---|
| `OPENAI_API_KEY` | For OpenAI provider |
| `ANTHROPIC_API_KEY` | For Anthropic provider |
| `GEMINI_API_KEY` / `GOOGLE_API_KEY` | For Gemini provider |
| `OPENAI_MODEL` / `ANTHROPIC_MODEL` / `GEMINI_MODEL` | Model overrides |

### OAuth

| Variable | Purpose |
|---|---|
| `OAUTH_BASE` | Server base URL |
| **`OAUTH_CLIENT_ID`** | Client ID |
| **`OAUTH_CLIENT_SECRET`** | Client secret |
| `OAUTH_REDIRECT_URI` | Callback URL |
| `OAUTH_SCOPE` | Scope |
| `OAUTH_LOGIN_METHOD` | Login method |

### DevAuth

| Variable | Purpose |
|---|---|
| `DEV_AUTH` | Set to `"1"` to enable |
| `DEV_AUTH_PASSPHRASE` | Optional passphrase |

### Jira

| Variable | Purpose |
|---|---|
| `JIRA_BASE_URL` | Server URL |
| **`JIRA_EMAIL`** | Service account email |
| **`JIRA_API_TOKEN`** | Service account token |
| `JIRA_PAGINATION` | Page size |
| `JIRA_LOG_LEVEL` | Log level |

### Confluence

| Variable | Purpose |
|---|---|
| `CONFLUENCE_BASE_URL` | Server URL |
| `CONFLUENCE_USER` | Service account user |
| `CONFLUENCE_API_TOKEN` | Service account token |
| `CONFLUENCE_LOG_LEVEL` | Log level |

### MS Graph

| Variable | Purpose |
|---|---|
| `MS_GRAPH_BASE` | Proxy base URL |
| `MS_GRAPH_API_KEY` | API key |
| `MS_GRAPH_UPN_DOMAIN` | Default UPN domain |
| `MS_GRAPH_OPEN_TIMEOUT` | Connect timeout |
| `MS_GRAPH_READ_TIMEOUT` | Read timeout |

</details>

## Example `.env`

```bash
# ── LLM ──────────────────────────────────────────────
AI_PROVIDER=merck_gw
GW_API_ROOT=https://iapi.merck.com/gpt/v2
GW_MODEL=gpt-4o
MERCK_GW_API_KEY=your-gateway-key

# ── OAuth SSO ────────────────────────────────────────
OAUTH_BASE=https://iapi.merck.com/authentication-service/v2
OAUTH_CLIENT_ID=your-client-id
OAUTH_CLIENT_SECRET=your-client-secret
OAUTH_REDIRECT_URI=https://yourapp.merck.com/auth/callback

# ── Jira ─────────────────────────────────────────────
JIRA_BASE_URL=https://issues.merck.com
JIRA_EMAIL=svc-account@merck.com
JIRA_API_TOKEN=your-jira-token

# ── Confluence (falls back to Jira creds if omitted) ─
# CONFLUENCE_BASE_URL=https://share.merck.com
# CONFLUENCE_USER=svc-account@merck.com
# CONFLUENCE_API_TOKEN=your-confluence-token

# ── MS Graph ─────────────────────────────────────────
MS_GRAPH_BASE=https://iapi.merck.com/microsoft-graph/v1.0
MS_GRAPH_API_KEY=your-graph-key

# ── Dev Auth (development only!) ─────────────────────
# DEV_AUTH=1
```

## Error handling

Each module defines its own `Error` class under its namespace:

```ruby
MerckTools::LLM::Error
MerckTools::Jira::Error
MerckTools::Confluence::Error
MerckTools::MSGraph::Error
```

All inherit from `StandardError`. Wrap calls in `rescue` blocks as needed:

```ruby
begin
  jira.search("project = MISSING")
rescue MerckTools::Jira::Error => e
  puts "Jira error: #{e.message}"
end
```

Note: Jira GET operations return `nil` on failure (with errors logged) rather
than raising. POST operations raise `Jira::Error`. This allows searches and
reads to degrade gracefully while writes surface errors immediately.

## Testing

```bash
bundle install
bundle exec rspec
```

Tests use [WebMock](https://github.com/bblimke/webmock) to stub all HTTP
requests. No real API credentials are needed to run the test suite.

## Architecture

```
MerckTools
├── LLM
│   ├── BaseClient          # Abstract interface (generate, stream)
│   ├── MerckGwClient       # Merck Azure-OpenAI gateway (Faraday)
│   ├── OpenAIClient        # Direct OpenAI API (net/http)
│   ├── RubyLLMClient       # Multi-provider via ruby_llm gem
│   └── MockClient          # Fallback / testing
├── Auth
│   ├── OAuthClient         # OAuth 2.0 SSO flows
│   └── DevAuth             # Dev-mode header-based auth
├── Jira::Client            # Jira REST API v3 (rest-client)
├── Confluence::Client      # Confluence REST API v1 (rest-client)
└── MSGraph::Client         # Microsoft Graph proxy (net/http)
```

All modules use `autoload` — only the modules you reference get loaded.

## License

Internal use only.
