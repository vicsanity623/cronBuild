#!/bin/bash
# =============================================================================
# CRONBUILD — One-Click Setup
# Run this once to install dependencies, configure API keys, and register the
# cron/launchd job. After this, your project builds itself automatically.
# =============================================================================

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        ${BOLD}CRONBUILD — Autonomous Setup${NC}${CYAN}           ║${NC}"
echo -e "${CYAN}║  Build anything. Automatically. On a schedule.  ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# --------------------------------------------------
# Detect project root (where this script lives)
# --------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_SRC="$PROJECT_DIR/autonomous.sh"
LOG_DIR="$HOME/.cronbuild"

# --------------------------------------------------
# 1. Check dependencies
# --------------------------------------------------
echo -e "${BOLD}[1/6] Checking dependencies...${NC}"

MISSING=""

check_dep() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "  ${YELLOW}✗ $1 not found${NC}"
    MISSING="$MISSING $1"
  else
    echo -e "  ${GREEN}✓ $1 installed${NC}"
  fi
}

check_dep "git"
check_dep "opencode"
check_dep "gh"
check_dep "perl"

if [ -n "$MISSING" ]; then
  echo ""
  echo -e "${YELLOW}Some dependencies are missing.${NC}"
  echo -e "  ${BOLD}opencode${NC} — Install: curl -fsSL https://opencode.ai/install.sh | bash"
  echo -e "  ${BOLD}gh${NC} (GitHub CLI) — Install: brew install gh  or  visit https://cli.github.com"
  echo -e "  ${BOLD}perl${NC} — Usually pre-installed on macOS/Linux"
  echo ""
  echo -e "Install them, then re-run this setup."
  exit 1
fi

# --------------------------------------------------
# 2. Ollama (optional)
# --------------------------------------------------
echo ""
echo -e "${BOLD}[2/6] Optional: Local models via Ollama...${NC}"
if command -v ollama &>/dev/null; then
  echo -e "  ${GREEN}✓ Ollama found${NC}"
  read -p "  Pull a coding model for offline fallback? (y/N): " PULL_OLLAMA
  if [[ "$PULL_OLLAMA" =~ ^[Yy]$ ]]; then
    echo -e "  Pulling qwen3.5-coder:9b (4.7 GB)..."
    ollama pull qwen3.5-coder:9b 2>&1 | tail -3
    echo -e "  ${GREEN}✓ Model ready${NC}"
  fi
else
  echo -e "  ${YELLOW}✗ Ollama not installed (optional — used as tertiary offline fallback)${NC}"
  echo -e "     Install later: brew install ollama  or  visit https://ollama.com"
fi

# --------------------------------------------------
# 3. GitHub Authentication
# --------------------------------------------------
echo ""
echo -e "${BOLD}[3/6] GitHub authentication...${NC}"
if gh auth status &>/dev/null; then
  echo -e "  ${GREEN}✓ Already authenticated as $(gh api user --jq .login 2>/dev/null)${NC}"
else
  echo -e "  ${YELLOW}Not authenticated. Starting login...${NC}"
  gh auth login
fi

# --------------------------------------------------
# 4. API Keys
# --------------------------------------------------
echo ""
echo -e "${BOLD}[4/6] API Keys (store in ~/.cronbuild/.env)${NC}"
mkdir -p "$LOG_DIR"
ENV_FILE="$LOG_DIR/.env"

if [ -f "$ENV_FILE" ]; then
  echo -e "  ${GREEN}✓ Found existing $ENV_FILE${NC}"
  read -p "  Overwrite? (y/N): " OVERWRITE
  if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
    rm -f "$ENV_FILE"
  fi
fi

if [ ! -f "$ENV_FILE" ]; then
  echo ""
  echo -e "  ${YELLOW}At least one API key is required.${NC}"
  echo -e "  Paid keys = higher rate limits = more builds per hour."
  echo -e "  Free keys work too but have stricter rate limits."
  echo ""

  # OpenRouter (recommended — gives access to 200+ models)
  read -p "  OpenRouter API key (skip with Enter): " OR_KEY
  if [ -n "$OR_KEY" ]; then
    echo "OPENROUTER_API_KEY=$OR_KEY" >> "$ENV_FILE"
    echo -e "  ${GREEN}✓ Saved OpenRouter key${NC}"
  fi

  # Google Gemini
  read -p "  Google Gemini API key (skip with Enter): " GEMINI_KEY
  if [ -n "$GEMINI_KEY" ]; then
    echo "GOOGLE_GEMINI_API_KEY=$GEMINI_KEY" >> "$ENV_FILE"
    echo -e "  ${GREEN}✓ Saved Gemini key${NC}"
  fi

  # DeepSeek
  read -p "  DeepSeek API key (skip with Enter): " DEEPSEEK_KEY
  if [ -n "$DEEPSEEK_KEY" ]; then
    echo "DEEPSEEK_API_KEY=$DEEPSEEK_KEY" >> "$ENV_FILE"
    echo -e "  ${GREEN}✓ Saved DeepSeek key${NC}"
  fi

  echo -e "  ${YELLOW}Keys saved to $ENV_FILE${NC}"
fi

echo ""
echo -e "${BOLD}[5/6] Checking project files...${NC}"
if [ ! -f "$PROJECT_DIR/DIRECTIVES.md" ]; then
  echo -e "  ${YELLOW}Creating default DIRECTIVES.md...${NC}"
  cp "$PROJECT_DIR/DIRECTIVES.md" "$PROJECT_DIR/DIRECTIVES.md" 2>/dev/null || true
fi
if [ ! -f "$PROJECT_DIR/MEMORY.md" ]; then
  echo -e "  ${YELLOW}Creating initial MEMORY.md...${NC}"
  cp "$PROJECT_DIR/MEMORY.md" "$PROJECT_DIR/MEMORY.md" 2>/dev/null || true
fi
echo -e "  ${GREEN}✓ Project files ready${NC}"

# --------------------------------------------------
# 6. Schedule the job
# --------------------------------------------------
echo ""
echo -e "${BOLD}[6/6] Scheduling autonomous runs...${NC}"

# Copy autonomous.sh to a stable location
CRON_SCRIPT="/usr/local/bin/cronbuild"
if [ ! -f "$CRON_SCRIPT" ]; then
  sudo cp "$SCRIPT_SRC" "$CRON_SCRIPT" 2>/dev/null || cp "$SCRIPT_SRC" "$CRON_SCRIPT"
  sudo chmod +x "$CRON_SCRIPT" 2>/dev/null || chmod +x "$CRON_SCRIPT"
  echo -e "  ${GREEN}✓ Installed to $CRON_SCRIPT${NC}"
else
  echo -e "  ${GREEN}✓ Already installed at $CRON_SCRIPT${NC}"
fi

echo ""
echo -e "  How often should CRONBUILD run?"
echo -e "  ${CYAN}1${NC}) Every hour        (aggressive — needs paid API)"
echo -e "  ${CYAN}2${NC}) Every 3 hours     (balanced)"
echo -e "  ${CYAN}3${NC)} Twice daily        (conservative — free API friendly)"
echo -e "  ${CYAN}4${NC}) Once daily         (gentle — best for free tier)"
echo -e "  ${CYAN}5${NC}) Custom cron expression"
echo ""

read -p "  Pick a schedule [1-5] (default: 4): " SCHED_CHOICE
SCHED_CHOICE=${SCHED_CHOICE:-4}

# write out crontab
CRON_EXPR=""
case "$SCHED_CHOICE" in
  1) CRON_EXPR="0 * * * *" ;;
  2) CRON_EXPR="0 */3 * * *" ;;
  3) CRON_EXPR="0 */12 * * *" ;;
  4) CRON_EXPR="0 0 * * *" ;;
  5) read -p "  Enter cron expression (e.g. '0 */6 * * *'): " CRON_EXPR ;;
  *) CRON_EXPR="0 0 * * *" ;;
esac

CRON_JOB="$CRON_EXPR $CRON_SCRIPT $PROJECT_DIR >> $LOG_DIR/cronbuild.log 2>&1"

# Check for existing job and remove it first
(crontab -l 2>/dev/null | grep -v "cronbuild" | grep -v "autonomous.sh") | crontab - 2>/dev/null || true
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab - 2>/dev/null

echo -e "  ${GREEN}✓ Cron job registered:${NC}"
echo -e "    ${CYAN}$CRON_JOB${NC}"
echo ""

# --------------------------------------------------
# Summary
# --------------------------------------------------
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ${BOLD}SETUP COMPLETE!${NC}${GREEN}                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Project:${NC}  $PROJECT_DIR"
echo -e "  ${BOLD}Schedule:${NC} $CRON_EXPR"
echo -e "  ${BOLD}Logs:${NC}     $LOG_DIR/cronbuild.log"
echo -e "  ${BOLD}Script:${NC}   $CRON_SCRIPT"
echo ""

echo -e "  ${YELLOW}What happens next:${NC}"
echo -e "  1. At the scheduled time, CRONBUILD will:"
echo -e "     a. Read MEMORY.md to understand project state"
echo -e "     b. Increment DAY counter"
echo -e "     c. Launch opencode with your project context"
echo -e "     d. AI creates a new feature, pushes a PR, and merges it"
echo -e "     e. MEMORY.md is updated for the next cycle"
echo -e "  2. You wake up to new features. Every day."
echo ""
echo -e "  ${BOLD}To run immediately (test):${NC}"
echo -e "    $CRON_SCRIPT $PROJECT_DIR"
echo ""
echo -e "  ${BOLD}To stop:${NC}"
echo -e "    crontab -e   (remove the cronbuild line)"
echo -e "  ${BOLD}To uninstall completely:${NC}"
echo -e "    $PROJECT_DIR/uninstall.sh"
echo ""
