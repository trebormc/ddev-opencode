[![tests](https://github.com/trebormc/ddev-opencode/actions/workflows/tests.yml/badge.svg)](https://github.com/trebormc/ddev-opencode/actions/workflows/tests.yml)

# ddev-opencode

A DDEV add-on that runs [OpenCode](https://github.com/opencode-ai/opencode) in a dedicated container for AI-powered Drupal development. OpenCode gets full access to your web container via Docker socket, enabling code generation, testing, static analysis, and browser automation.

For the best experience, pair this add-on with [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) -- 13 agents, 4 rules, and 14 skills built specifically for Drupal development.

## Quick Start

```bash
# 1. Install the add-on
ddev add-on get trebormc/ddev-opencode

# 2. Clone the Drupal AI agents
git clone https://github.com/trebormc/drupal-ai-agents.git ~/drupal-ai-agents

# 3. Set up your API credentials
mkdir -p ~/opencode-auth
cat > ~/opencode-auth/auth.json << 'EOF'
{
  "anthropic": {
    "type": "oauth",
    "access": "sk-ant-oat01-YOUR_ACCESS_TOKEN",
    "refresh": "sk-ant-ort01-YOUR_REFRESH_TOKEN",
    "expires": 0
  }
}
EOF

# 4. Configure the environment
ddev dotenv set .ddev/.env.opencode \
  --host-opencode-auth-dir="$HOME/opencode-auth/" \
  --host-opencode-config-dir="$HOME/drupal-ai-agents/"

# 5. Restart DDEV
ddev restart

# 6. Launch OpenCode
ddev opencode
```

## Prerequisites

- [DDEV](https://ddev.readthedocs.io/) >= v1.23.5
- An API key (Anthropic, OpenAI, or a LiteLLM proxy)

## Installation

```bash
ddev add-on get trebormc/ddev-opencode
```

This automatically installs [ddev-playwright-mcp](https://github.com/trebormc/ddev-playwright-mcp) (browser automation) and [ddev-beads](https://github.com/trebormc/ddev-beads) (task tracking) as dependencies.

## Configuration

After installation, edit `.ddev/.env.opencode`:

```bash
# Directory containing auth.json with your API keys
HOST_OPENCODE_AUTH_DIR=${HOME}/opencode-auth/

# Directory containing opencode.json, agents, rules, and skills
# Point this to your drupal-ai-agents clone for Drupal-specific agents
HOST_OPENCODE_CONFIG_DIR=${HOME}/drupal-ai-agents/

# Timezone
TZ=UTC
```

### Authentication

Create an `auth.json` file in the directory pointed to by `HOST_OPENCODE_AUTH_DIR`:

```json
{
  "anthropic": {
    "type": "oauth",
    "access": "sk-ant-oat01-YOUR_ACCESS_TOKEN",
    "refresh": "sk-ant-ort01-YOUR_REFRESH_TOKEN",
    "expires": 0
  }
}
```

### OpenCode Configuration

The `HOST_OPENCODE_CONFIG_DIR` should contain an `opencode.json` file with your model preferences, permissions, and MCP settings. The [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) repository includes a ready-to-use `opencode.json.example` that you can copy and customize:

```bash
cd ~/drupal-ai-agents
cp opencode.json.example opencode.json
vi opencode.json
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    DDEV Network                      │
│                                                      │
│  ┌──────────────┐    docker exec    ┌─────────────┐ │
│  │   OpenCode   │─────────────────>│     Web      │ │
│  │  Container   │                   │  Container   │ │
│  │              │                   │  (Drupal)    │ │
│  │  - opencode  │                   │  - drush     │ │
│  │  - node 22   │                   │  - phpunit   │ │
│  │              │                   │  - phpstan   │ │
│  └──────┬───────┘                   └─────────────┘ │
│         │                                            │
│         ├── HTTP (MCP)                               │
│         v                                            │
│  ┌──────────────────┐  ┌──────────────────┐          │
│  │  Playwright MCP  │  │     Beads        │          │
│  │    Container     │  │   (bd tasks)     │          │
│  │  (browser tests) │  └──────────────────┘          │
│  └──────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

OpenCode communicates with the web container via `docker exec` (through the mounted Docker socket), giving the AI agent full CLI access to drush, composer, phpunit, phpstan, and any other tool in the web container.

Playwright MCP is accessed over HTTP for browser automation and visual testing.

## Commands

### `ddev opencode`

Launch the OpenCode TUI (Terminal User Interface):

```bash
ddev opencode

# With a custom tab title
ddev opencode tui My Feature Work
```

### `ddev opencode shell`

Open a bash shell in the OpenCode container:

```bash
ddev opencode shell
```

Inside the shell you have access to helper functions:

- `drush` -- Run drush commands in the web container
- `composer` -- Run composer in the web container
- `phpunit` -- Run PHPUnit in the web container
- `phpstan` -- Run PHPStan in the web container
- `web-shell` -- Open an interactive shell in the web container
- `web-exec` -- Execute any command in the web container

## Desktop Notifications

OpenCode can send desktop notifications to your host when tasks complete or need attention. If you use [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents), the notification configuration is included by default (`opencode-notifier.json`).

To receive notifications, start the notification bridge on your host:

```bash
# From the DDEV AI workspace
./scripts/start-notify-bridge.sh
```

See the [DDEV AI workspace](https://github.com/trebormc/ddev-ai-workspace) for full notification setup details.

## Autonomous Execution

For autonomous task execution (overnight runs), see the separate [ddev-ralph](https://github.com/trebormc/ddev-ralph) add-on.

## Related

- [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) -- 13 agents, 4 rules, 14 skills for Drupal development
- [ddev-beads](https://github.com/trebormc/ddev-beads) -- Beads task tracker (auto-installed)
- [ddev-playwright-mcp](https://github.com/trebormc/ddev-playwright-mcp) -- Playwright browser automation (auto-installed)
- [ddev-claude-code](https://github.com/trebormc/ddev-claude-code) -- Alternative: Claude Code AI for DDEV
- [ddev-ralph](https://github.com/trebormc/ddev-ralph) -- Autonomous task runner

## Disclaimer

This project is not affiliated with Anthropic, OpenCode, Beads, Playwright, Microsoft, or DDEV. AI-generated code may contain errors -- always review changes before deploying to production. See [menetray.com](https://menetray.com) for more information and [DruScan](https://druscan.com) for Drupal auditing tools.

## License

Apache-2.0. See [LICENSE](LICENSE).
