[![tests](https://github.com/trebormc/ddev-opencode/actions/workflows/tests.yml/badge.svg)](https://github.com/trebormc/ddev-opencode/actions/workflows/tests.yml)

# ddev-opencode

A DDEV add-on that runs [OpenCode](https://github.com/opencode-ai/opencode) in a dedicated container for AI-powered Drupal development.

For the best experience, pair this add-on with [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) -- 13 agents, 4 rules, and 14 skills built specifically for Drupal development.

## Quick Start

```bash
# 1. Install the add-on
ddev add-on get trebormc/ddev-opencode

# 2. Set up your API credentials
mkdir -p ~/opencode-auth
cp share/auth.json.example ~/opencode-auth/auth.json
# Edit ~/opencode-auth/auth.json with your API tokens

# 3. Point to your config and auth directories
ddev dotenv set .ddev/.env.opencode \
  --host-opencode-auth-dir="$HOME/opencode-auth/" \
  --host-opencode-config-dir="$HOME/drupal-ai-agents/"

# 4. Restart DDEV
ddev restart

# 5. Launch OpenCode
ddev opencode
```

## Prerequisites

- [DDEV](https://ddev.readthedocs.io/) >= v1.23.5
- An API key (Anthropic, OpenAI, or a LiteLLM proxy)

## Installation

```bash
ddev add-on get trebormc/ddev-opencode
ddev restart
```

This automatically installs [ddev-playwright-mcp](https://github.com/trebormc/ddev-playwright-mcp) (browser automation) and [ddev-beads](https://github.com/trebormc/ddev-beads) (task tracking) as dependencies.

## Authentication

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

Credentials are stored in a shared directory on the host (`~/opencode-auth/` by default), so you only need to configure them **once** -- all your DDEV projects share the same credentials automatically.

## Configuration

After installation, environment variables are in `.ddev/.env.opencode`:

```bash
# Directory containing auth.json with your API keys.
# Shared across ALL DDEV projects. Change only if you need a custom location.
HOST_OPENCODE_AUTH_DIR=${HOME}/opencode-auth/

# Directory containing opencode.json, agents, rules, and skills.
# Point this to your drupal-ai-agents clone for Drupal-specific agents.
HOST_OPENCODE_CONFIG_DIR=${HOME}/drupal-ai-agents/

# Timezone
TZ=UTC
```

### OpenCode Configuration

The `HOST_OPENCODE_CONFIG_DIR` should contain an `opencode.json` file with your model preferences, permissions, and MCP settings. The [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) repository includes a ready-to-use `opencode.json.example`:

```bash
cd ~/drupal-ai-agents
cp opencode.json.example opencode.json
# Edit opencode.json with your preferences
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              DDEV Docker Network                 │
│                                                  │
│  ┌──────────────┐  docker exec  ┌────────────┐  │
│  │   OpenCode   │──────────────>│    Web     │  │
│  │  Container   │               │  (Drupal)  │  │
│  └──────┬───────┘               └────────────┘  │
│         │ MCP HTTP                               │
│         v                                        │
│  ┌──────────────┐  ┌──────────────┐              │
│  │  Playwright  │  │    Beads     │              │
│  │     MCP      │  │  (bd tasks)  │              │
│  └──────────────┘  └──────────────┘              │
└─────────────────────────────────────────────────┘
```

OpenCode communicates with the web container via `docker exec` (through the mounted Docker socket), giving it full CLI access to drush, composer, phpunit, phpstan, and any other tool in the web container. Playwright MCP is accessed over HTTP for browser automation and visual testing.

## Commands

| Command | Description |
|---------|-------------|
| `ddev opencode` | Launch the OpenCode TUI |
| `ddev opencode tui [title]` | Launch TUI with a custom tab title |
| `ddev opencode shell` | Open a bash shell in the container |
| `ddev opencode <command>` | Run any command in the container |

### Shell Helpers

Inside the container (via `ddev opencode shell`), these helper functions are available:

| Helper | Description |
|--------|-------------|
| `drush` | Run drush commands in the web container |
| `composer` | Run composer in the web container |
| `web-exec` | Execute any command in the web container |
| `web-shell` | Open an interactive shell in the web container |
| `bd` | Run Beads task tracking commands |

## Desktop Notifications

OpenCode can send desktop notifications when tasks complete or need attention. If you use [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents), the notification configuration is included by default.

To receive notifications, start the notification bridge on your host:

```bash
./scripts/start-notify-bridge.sh
```

See the [DDEV AI workspace](https://github.com/trebormc/ddev-ai-workspace) for full notification setup details.

## Autonomous Execution

For autonomous task execution (overnight runs), see [ddev-ralph](https://github.com/trebormc/ddev-ralph).

## Related

- [drupal-ai-agents](https://github.com/trebormc/drupal-ai-agents) -- 13 agents, 4 rules, 14 skills for Drupal development
- [ddev-claude-code](https://github.com/trebormc/ddev-claude-code) -- Alternative: Claude Code AI for DDEV
- [ddev-ralph](https://github.com/trebormc/ddev-ralph) -- Autonomous task runner
- [ddev-beads](https://github.com/trebormc/ddev-beads) -- Beads task tracker (auto-installed)
- [ddev-playwright-mcp](https://github.com/trebormc/ddev-playwright-mcp) -- Playwright browser automation (auto-installed)

## Disclaimer

This project is not affiliated with Anthropic, OpenCode, Beads, Playwright, Microsoft, or DDEV. AI-generated code may contain errors -- always review changes before deploying to production. See [menetray.com](https://menetray.com) for more information and [DruScan](https://druscan.com) for Drupal auditing tools.

## License

Apache-2.0. See [LICENSE](LICENSE).
