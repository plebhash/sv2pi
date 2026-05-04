#!/bin/sh
set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

banner() {
    B='\033[0;36m'  # cyan
    Nc='\033[0m'
    printf '\n%b' "$B"
    printf '╔════════════════╗\n'
    printf '║ 🤖 sv2pi.sh  ⛏️ ║\n'
    printf '╚════════════════╝\n'
    printf '\n'
    printf '%ba Pi Skill for agentic production deployments of the Sv2 Reference Implementation.%b\n' "${GREEN}" "${NC}"
    printf '%b\n' "$Nc"
}

err() { printf '%bERROR:%b %s\n' "${RED}" "${NC}" "$*" >&2; }
warn() { printf '%bWARN:%b %s\n' "${YELLOW}" "${NC}" "$*" >&2; }
ok() { printf '%bOK:%b %s\n' "${GREEN}" "${NC}" "$*"; }

banner

printf '⚠️ warning ⚠️\n\n'
printf '%bsv2pi is provided as-is with no guarantees.%b\n' "${YELLOW}" "${NC}"
printf '%bthe author is not responsible for any damage this skill may cause to your system.%b\n' "${YELLOW}" "${NC}"
printf '%buse it at your own risk.%b\n' "${YELLOW}" "${NC}"
printf '\n⚠️ warning ⚠️\n'
printf '\n'

# ─── environment setup ───────────────────────────────────────────

# Piped curl runs in a stripped shell. Scan common node/npm paths.
OLD_PATH="$PATH"
for base in \
    "$HOME/.nvm" \
    "$HOME/.local/share/fnm" \
    "$HOME/.asdf/installs/nodejs" \
    "$HOME/.local" \
    "$HOME/bin" \
    /usr/local/bin; do
    case "$base" in
        */nodejs) for d in "$base"/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done 2>/dev/null ;;
        *) [ -d "$base/versions/node" ] && for d in "$base/versions/node"/*/bin; do [ -d "$d" ] && PATH="$d:$PATH"; done 2>/dev/null ;;
    esac
done
# Source nvm explicitly if available
[ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" 2>/dev/null || true
# Fallback: scan for npm/pi in common global locations
for d in "$HOME/.npm-global/bin" /usr/local/lib/node_modules/.bin; do
    [ -d "$d" ] && PATH="$d:$PATH"
done

# ─── prerequisites ──────────────────────────────────────────────

printf 'Checking prerequisites...\n'

# Check npm
npm_path=''
for cmd in npm; do
    if npm_path=$(command -v "$cmd" 2>/dev/null) && [ -n "$npm_path" ]; then
        ok "npm $($npm_path --version 2>/dev/null)"
        break
    fi
done
if [ -z "${npm_path:-}" ]; then
    err "npm not found."
    echo ''
    echo '  npm is required for Pi package management.'
    echo '  Install Node.js (includes npm): https://nodejs.org/'
    echo '  Or run: curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'
    echo ''
    exit 1
fi
NPM="$npm_path"

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    err "Docker not found."
    echo ''
    echo '  Docker is required for SRI container deployment.'
    echo '  Install: https://docs.docker.com/engine/install/'
    echo '  Or: sudo apt install -y docker.io && sudo usermod -aG docker $USER'
    echo ''
    exit 1
fi
ok "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"

# Check Pi
pi_path=''
pi_path=$(command -v pi 2>/dev/null) || pi_path=''
if [ -z "$pi_path" ]; then
    err "Pi Coding Agent not found."
    echo ''
    echo '  Pi is the agent harness that runs sv2pi.'
    echo '  Install: https://pi.dev/docs/latest'
    echo ''
    echo '  Quick install:'
    echo '    curl -fsSL https://pi.dev/install.sh | sh'
    echo '    # or'
    echo '    npm install -g @mariozechner/pi-coding-agent'
    echo ''
    exit 1
fi
ok "pi installed"

# ─── auth check ──────────────────────────────────────────────────

AUTH_OK=0

# Check for API key env vars (common providers)
for var in ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY DEEPSEEK_API_KEY GROQ_API_KEY CEREBRAS_API_KEY XAI_API_KEY MISTRAL_API_KEY OPENROUTER_API_KEY; do
    eval "val=\${$var:-}"
    if [ -n "$val" ]; then
        ok "auth: $var is set"
        AUTH_OK=1
        break
    fi
done

# Check OAuth auth.json (more than empty object)
if [ "$AUTH_OK" -eq 0 ] && [ -f "$HOME/.pi/agent/auth.json" ]; then
    AUTH_SIZE=$(wc -c < "$HOME/.pi/agent/auth.json" 2>/dev/null || echo 0)
    if [ "$AUTH_SIZE" -gt 3 ]; then
        ok "auth: OAuth token found"
        AUTH_OK=1
    fi
fi

# Check models.json for custom provider API keys
if [ "$AUTH_OK" -eq 0 ] && [ -f "$HOME/.pi/agent/models.json" ]; then
    if grep -q '"apiKey"' "$HOME/.pi/agent/models.json" 2>/dev/null; then
        ok "auth: custom provider API key found in models.json"
        AUTH_OK=1
    fi
fi

if [ "$AUTH_OK" -eq 0 ]; then
    err 'Pi is not authenticated.'
    echo ''
    printf '  No API key found and no OAuth session. Authenticate with:\n\n'
    printf '    %bpi (then type %b/login%b inside the TUI)%b\n' "${CYAN}" "${NC}" "${CYAN}" "${NC}"
    echo ''
    echo '  After login, run this script again.'
    exit 1
fi

# ─── permission ─────────────────────────────────────────────────

echo ''
printf '%bsv2pi installs the SRI production deployment skill via:%b\n' "${YELLOW}" "${NC}"
echo ''
printf '%b  pi install git:github.com/plebhash/sv2pi%b\n' "${CYAN}" "${NC}"
echo ''

printf 'Proceed with install? [y/N] '
read -r answer < /dev/tty 2>/dev/null || read -r answer
case "$answer" in
    [yY]|[yY][eE][sS]) ;;
    *) echo 'Aborted.'; exit 0 ;;
esac

# ─── install skill ──────────────────────────────────────────────

echo ''
echo 'Installing sv2pi skill...'
pi install git:github.com/plebhash/sv2pi
ok 'sv2pi skill installed'

# ─── launch ─────────────────────────────────────────────────────

echo ''
printf '%bLaunching Pi with sv2pi...%b\n' "${GREEN}" "${NC}"
echo ''
exec pi 'we just installed the sv2pi skill — give me a summary of what the skill can do and what SRI apps it can deploy' < /dev/tty
