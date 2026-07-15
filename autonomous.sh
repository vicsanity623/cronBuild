#!/bin/bash
# =============================================================================
# CRONBUILD — Autonomous AI Development Engine
# =============================================================================
# This script drives an autonomous software development loop:
#   1. Read MEMORY.md → understand current state & next target
#   2. Increment day counter
#   3. Launch opencode with a crafted prompt for the AI agent
#   4. AI agent implements features, creates PR, merges to main
#   5. Update MEMORY.md with completed work & next target
#   6. Retry on failure — guaranteed forward progress
# =============================================================================
# Usage:
#   ./autonomous.sh [project-directory]
#
# If no directory is provided, uses the current working directory.
#
# Environment variables (set in ~/.cronbuild/.env or export):
#   OPENROUTER_API_KEY   - OpenRouter key (primary paid tier, 200+ models)
#   GOOGLE_GEMINI_API_KEY - Google Gemini key (secondary fallback)
#   DEEPSEEK_API_KEY      - DeepSeek key (tertiary fallback)
#   GITHUB_TOKEN          - GitHub personal access token (or use `gh auth`)
#
# CRONBUILD uses a 3-tier model cascade for resilience:
#   Tier 1: OpenRouter (paid, many models)       ← recommended primary
#   Tier 2: Google Gemini 2.5 Flash (paid/free)   ← fallback
#   Tier 3: Local Ollama (offline, no API cost)   ← last resort
# =============================================================================

set -e

# ─── Configuration ────────────────────────────────────────────────────────────
PROJECT_DIR="${1:-$(pwd)}"
MEMORY_FILE="$PROJECT_DIR/MEMORY.md"
DIRECTIVES_FILE="$PROJECT_DIR/DIRECTIVES.md"
CONFIG_DIR="$HOME/.cronbuild"
LOG_DIR="$CONFIG_DIR"
LOG_FILE="$LOG_DIR/cronbuild.log"
ENV_FILE="$CONFIG_DIR/.env"
LOCKFILE="/tmp/cronbuild_$(echo "$PROJECT_DIR" | md5 -r 2>/dev/null | cut -d' ' -f1 || echo "$PROJECT_DIR" | shasum | cut -d' ' -f1).lock"
MAX_RETRIES=10
RETRY_DELAY=60
COMPACT_THRESHOLD=4  # Compact MEMORY.md when DAY >= this value

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ─── Load API keys ────────────────────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

# ─── Helper: Log ──────────────────────────────────────────────────────────────
log() {
  local LEVEL="$1"; shift
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$LEVEL] $*" >> "$LOG_FILE"
}

info()  { log "INFO" "$@"; echo -e "  ${CYAN}INFO:${NC} $*"; }
warn()  { log "WARN" "$@"; echo -e "  ${YELLOW}WARN:${NC} $*"; }
ok()    { log "OK"   "$@"; echo -e "  ${GREEN}OK:${NC}   $*"; }
fail()  { log "FAIL" "$@"; echo -e "  ${RED}FAIL:${NC}  $*"; }

# ─── Lock file (prevents concurrent runs) ─────────────────────────────────────
acquire_lock() {
  if [ -f "$LOCKFILE" ]; then
    PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      fail "Another CRONBUILD instance (PID $PID) is already running. Exiting."
      exit 0
    else
      rm -f "$LOCKFILE"
    fi
  fi
  echo $$ > "$LOCKFILE"
}

cleanup() {
  rm -f "$LOCKFILE"
  cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

  # Keep only the most recent opencode session
  local SESSION_DIR="$HOME/.local/share/opencode/storage/session_diff"
  if [ -d "$SESSION_DIR" ]; then
    ls -t "$SESSION_DIR"/ses_*.json 2>/dev/null | tail -n +2 | while read -r OLD_SESSION; do
      rm -f "$OLD_SESSION"
    done 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# ─── MEMORY.md operations ─────────────────────────────────────────────────────
get_last_day() {
  grep -o '\[DAY [0-9]*\]' "$MEMORY_FILE" 2>/dev/null | tail -1 | grep -o '[0-9]*' || echo "0"
}

get_last_target() {
  grep '| NEXT:' "$MEMORY_FILE" 2>/dev/null | tail -1 | sed 's/.*| NEXT: //' || echo ""
}

compact_memory() {
  local LAST_DAY="$1"
  info "Memory has reached Day ${LAST_DAY}. Running Compaction Protocol..."

  local LAST_LINE
  LAST_LINE=$(grep '\[DAY ' "$MEMORY_FILE" 2>/dev/null | tail -1)
  local COMPACTED_LINE
  COMPACTED_LINE=$(echo "$LAST_LINE" | sed -E 's/\[DAY [0-9]+\]/[DAY 1]/')

  cat <<EOF > "$MEMORY_FILE"
# PROJECT MEMORY LOG
*Format: [DAY X] | [DATE] | [COMPLETED] | [NEXT DAY TARGET]*

$COMPACTED_LINE
EOF

  git add "$MEMORY_FILE" >> "$LOG_FILE" 2>&1
  git commit -m "chore: compact memory log to Day 1 baseline" >> "$LOG_FILE" 2>&1
  git push origin main >> "$LOG_FILE" 2>&1 || true

  info "Memory compacted. State reset to Day 1."
}

# ─── Prompt generation ────────────────────────────────────────────────────────
generate_prompt() {
  local NEXT_DAY="$1"
  local TODAY="$2"
  local LAST_DAY="$3"
  local LAST_TARGET="$4"
  local EXTRA="$5"
  local MODEL_TYPE="$6"  # "deepseek", "gemini", or "ollama"

  # Base prompt shared across all models
  local BASE="You are AI-1 (Developer and Merge Master), an autonomous developer agent.
Your goal: implement the Day $NEXT_DAY features, create a PR, squash-merge it, and update MEMORY.md.

CRITICAL: You are in AUTO-APPROVE mode. Execute commands immediately. Never ask for permission.

Context:
- Project directory: $PROJECT_DIR
- Today: $TODAY
- Session Goal: Day $NEXT_DAY (Last completed: Day $LAST_DAY)
- Implementation Target: $LAST_TARGET
$EXTRA

Execute each phase using your tools:

Phase 1: Read
- Read MEMORY.md to verify state.
- Read DIRECTIVES.md to align with development standards.

Phase 2: Implement
- Implement the next incremental target: $LAST_TARGET. Do NOT rewrite the whole codebase.
- Run any available tests to verify.

Phase 3: Branch and Commit
- git checkout -b day-$NEXT_DAY-feature
- git add .
- git commit -m 'feat: day $NEXT_DAY implementation of $LAST_TARGET'
- git push -u origin day-$NEXT_DAY-feature

Phase 4: Create Pull Request
- gh pr create --title 'Day $NEXT_DAY: $LAST_TARGET' --body 'Automated autonomous implementation for Day $NEXT_DAY.'

Phase 5: Merge
- gh pr merge --squash --delete-branch
- If the merge fails, fix any errors and retry.

Phase 6: Update Memory on Main
- git checkout main && git pull origin main
- Append EXACTLY one line to MEMORY.md: [DAY $NEXT_DAY] | $TODAY | <completed features> | NEXT: <next target>
- git add MEMORY.md && git commit -m 'day $NEXT_DAY memory update' && git push origin main

Rules:
- AUTO-APPROVE mode: Never ask for user permission.
- Use fully qualified args in gh commands (no interactive prompts).
- Ensure the PR is merged and MEMORY.md is pushed on main before completing."

  if [ "$MODEL_TYPE" = "deepseek" ]; then
    echo "Hi and welcome to Day $NEXT_DAY of development!

Today is $TODAY. The last day completed was Day $LAST_DAY.
Last session target: $LAST_TARGET

$EXTRA

Please follow the Directives in DIRECTIVES.md exactly:
1. Read MEMORY.md to understand project state and to obtain the last day completed — $LAST_DAY.
2. As AI-1 (Developer & Merge Master), create a new git branch, implement the next features, and create a Pull Request.

IMPERATIVE RULES (you MUST follow every one):
- Work incrementally, one feature at a time. Do NOT rewrite the entire project.
- Create a branch named day-$NEXT_DAY-feature and push it to origin.
- Use gh pr create to open a Pull Request to main with a descriptive title and summary.
- After the PR passes, MERGE IT using gh pr merge --squash or gh pr merge --merge.
- After merge, append EXACTLY one line to MEMORY.md:
  [DAY $NEXT_DAY] | $TODAY | <completed features> | NEXT: <next target>
- Push the MEMORY.md update to main: git add MEMORY.md && git commit -m day-$NEXT_DAY && git push
- If tests fail or there are merge conflicts, fix them and try again.
- YOU MUST END WITH A SUCCESSFUL MERGE. Do not stop until the PR is merged and MEMORY.md is updated on main.

Your GitHub token is available. Use gh for all GitHub operations.
Let's build, one day at a time!"
  elif [ "$MODEL_TYPE" = "gemini" ]; then
    echo "You are AI-1 (Developer and Merge Master), an autonomous developer agent operating inside OpenCode.
Your ultimate goal is to implement the day's feature, create a PR, squash-merge it, and update MEMORY.md.
CRITICAL: You are equipped with terminal execution tools (bash). You MUST execute terminal commands using your tool.
Do NOT just print markdown code blocks or tell the user what to run. Do the work yourself.

Context:
- Project: $(basename "$PROJECT_DIR")
- Today: $TODAY
- Session Goal: Day $NEXT_DAY (Last completed: Day $LAST_DAY)
- Implementation Target: $LAST_TARGET
$EXTRA

Execute each phase sequentially using your terminal execution tool:

Phase 1: Verify and Read
- Read MEMORY.md to verify state.
- Read DIRECTIVES.md to align with development standards.

Phase 2: Implement and Verify
- Implement the next incremental target: $LAST_TARGET. Do NOT rewrite the whole codebase; build incrementally.
- Run local tests to verify your code behaves.

Phase 3: Branch and Commit
- git checkout -b day-$NEXT_DAY-feature
- git add .
- git commit -m 'feat: day $NEXT_DAY implementation of $LAST_TARGET'
- git push -u origin day-$NEXT_DAY-feature

Phase 4: Non-Interactive Pull Request
- gh pr create --title 'Day $NEXT_DAY: $LAST_TARGET' --body 'Automated autonomous implementation for Day $NEXT_DAY.'

Phase 5: Non-Interactive Merge
- gh pr merge --squash --delete-branch
- If the merge fails, fix any errors and execute the merge command again.

Phase 6: Update Memory on Main
- git checkout main && git pull origin main
- Append EXACTLY one line to MEMORY.md: [DAY $NEXT_DAY] | $TODAY | <completed features> | NEXT: <next target>
- git add MEMORY.md && git commit -m 'day $NEXT_DAY memory update' && git push origin main

Rules:
- You are in AUTO-APPROVE mode. Never ask for user permission or wait for confirmations.
- Always use fully qualified arguments in gh commands to bypass CLI interactivity.
- Ensure the PR is merged and MEMORY.md is pushed on main before completing your execution."
  else
    # ollama - stripped down, no chit-chat
    echo "You are AI-1 (Developer and Merge Master), an autonomous developer agent.
Goal: implement Day $NEXT_DAY features, create PR, squash-merge, update MEMORY.md.

CRITICAL: AUTO-APPROVE mode. Execute immediately. No greetings. No questions.

Context:
- Project: $(basename "$PROJECT_DIR")
- Day $NEXT_DAY (Last: $LAST_DAY)
- Target: $LAST_TARGET

Execute:
1. Read MEMORY.md and DIRECTIVES.md
2. Implement $LAST_TARGET incrementally
3. git checkout -b day-$NEXT_DAY-feature && git add . && git commit -m 'feat: day $NEXT_DAY' && git push -u origin day-$NEXT_DAY-feature
4. gh pr create --title 'Day $NEXT_DAY: $LAST_TARGET' --body 'Automated.'
5. gh pr merge --squash --delete-branch
6. git checkout main && git pull origin main
7. Append [DAY $NEXT_DAY] | $TODAY | <completed> | NEXT: <next target> to MEMORY.md
8. git add MEMORY.md && git commit -m 'day $NEXT_DAY' && git push

Rules: AUTO-APPROVE. Never ask. Do not converse. Execute only."
  fi
}

# ─── Model runner ─────────────────────────────────────────────────────────────
run_opencode() {
  local PROMPT="$1"
  local MODEL="$2"
  local TIMEOUT="$3"
  local OUT_FILE="$4"

  perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" opencode run "$PROMPT" --model "$MODEL" --auto > "$OUT_FILE" 2>&1
  return $?
}

check_memory_advance() {
  git pull origin main >> "$LOG_FILE" 2>&1
  local CURRENT_DAY
  CURRENT_DAY=$(get_last_day)
  CURRENT_DAY=${CURRENT_DAY:-0}
  echo "$CURRENT_DAY"
}

# ─── Main autonomous loop ─────────────────────────────────────────────────────
main() {
  echo "========================================" >> "$LOG_FILE"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [START] CRONBUILD autonomous cycle" >> "$LOG_FILE"

  info "Project directory: $PROJECT_DIR"

  if [ ! -d "$PROJECT_DIR" ]; then
    fail "Project directory does not exist: $PROJECT_DIR"
    exit 1
  fi

  if [ ! -f "$MEMORY_FILE" ]; then
    fail "MEMORY.md not found in $PROJECT_DIR. Run setup.sh first."
    exit 1
  fi

  if [ ! -f "$DIRECTIVES_FILE" ]; then
    fail "DIRECTIVES.md not found in $PROJECT_DIR. Run setup.sh first."
    exit 1
  fi

  cd "$PROJECT_DIR" || exit 1

  # Ensure we're in a git repo
  if [ ! -d ".git" ]; then
    fail "Not a git repository. Initialize with: git init && git add . && git commit -m 'initial'"
    exit 1
  fi

  # Sync log
  cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

  # ── Sync with main ──────────────────────────────────────────────────────────
  info "Syncing with remote..."
  git fetch origin >> "$LOG_FILE" 2>&1 || true
  git stash >> "$LOG_FILE" 2>&1 || true
  git checkout main >> "$LOG_FILE" 2>&1 || true
  git pull origin main >> "$LOG_FILE" 2>&1 || true

  # ── Memory Compaction (prevent bloat) ────────────────────────────────────────
  LAST_DAY=$(get_last_day)
  LAST_DAY=${LAST_DAY:-0}

  if [ "$LAST_DAY" -ge "$COMPACT_THRESHOLD" ]; then
    compact_memory "$LAST_DAY"
  fi

  # ── Day Counting ─────────────────────────────────────────────────────────────
  LAST_DAY=$(get_last_day)
  LAST_DAY=${LAST_DAY:-0}
  NEXT_DAY=$((LAST_DAY + 1))
  TODAY=$(date '+%Y-%m-%d')
  LAST_TARGET=$(get_last_target)

  echo "========================================" >> "$LOG_FILE"
  info "[DAY $NEXT_DAY] Starting autonomous cycle"
  info "  Previous target: $LAST_TARGET"
  info "  Max retries: $MAX_RETRIES"

  cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

  # ── Retry Loop ───────────────────────────────────────────────────────────────
  for ((ATTEMPT=1; ATTEMPT<=MAX_RETRIES; ATTEMPT++)); do
    info "[DAY $NEXT_DAY] Attempt $ATTEMPT/$MAX_RETRIES"
    cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

    if [ "$ATTEMPT" -eq 1 ]; then
      EXTRA_PROMPT=""
    else
      EXTRA_PROMPT="IMPORTANT: Previous attempt $((ATTEMPT-1)) failed to merge.
Analyze what went wrong, fix any errors, and ensure this attempt succeeds.
Do NOT repeat the same approach — fix the root cause and merge successfully."
    fi

    # Determine available model cascade
    DEEPSEEK_AVAILABLE=0
    GEMINI_AVAILABLE=0
    OLLAMA_AVAILABLE=0

    if [ -n "$DEEPSEEK_API_KEY" ]; then
      DEEPSEEK_AVAILABLE=1
    fi
    if [ -n "$GOOGLE_GEMINI_API_KEY" ]; then
      GEMINI_AVAILABLE=1
    fi
    if command -v ollama &>/dev/null && ollama list 2>/dev/null | grep -q "qwen3.5-coder"; then
      OLLAMA_AVAILABLE=1
    fi

    # If no keys at all, try OpenRouter with opencode's default or fallback to Ollama
    if [ "$DEEPSEEK_AVAILABLE" -eq 0 ] && [ "$GEMINI_AVAILABLE" -eq 0 ]; then
      if [ -n "$OPENROUTER_API_KEY" ]; then
        # OpenRouter models can be used via opencode's openrouter/ namespace
        DEEPSEEK_AVAILABLE=1
        GEMINI_AVAILABLE=1
      elif [ "$OLLAMA_AVAILABLE" -eq 1 ]; then
        info "No API keys found. Using local Ollama as primary."
      else
        warn "No API keys configured and Ollama not available."
        warn "Set up at least one API key in ~/.cronbuild/.env or install Ollama."
        sleep "$RETRY_DELAY"
        continue
      fi
    fi

    # Clean workspace before each attempt
    git reset --hard HEAD >> "$LOG_FILE" 2>&1
    git clean -fd >> "$LOG_FILE" 2>&1
    git fetch origin >> "$LOG_FILE" 2>&1
    git checkout main >> "$LOG_FILE" 2>&1
    git pull origin main >> "$LOG_FILE" 2>&1

    # Kill any lingering opencode processes
    pkill -9 -f "opencode.*$PROJECT_DIR" 2>/dev/null || true
    sleep 2

    # ── Model Chain Execution ──────────────────────────────────────────────────
    TRIAL_FAILED=0

    # Tier 1: DeepSeek (via OpenRouter if key available, or opencode free tier)
    TIER1_FAILED=1
    info "[Model Tier 1/3] Attempting DeepSeek..."
    TEMP_OUT=$(mktemp)
    if [ -n "$OPENROUTER_API_KEY" ] && [ -n "$OPENROUTER_MODEL" ]; then
      PROMPT=$(generate_prompt "$NEXT_DAY" "$TODAY" "$LAST_DAY" "$LAST_TARGET" "$EXTRA_PROMPT" "deepseek")
      run_opencode "$PROMPT" "openrouter/$OPENROUTER_MODEL" 300 "$TEMP_OUT"
    elif [ -n "$DEEPSEEK_API_KEY" ]; then
      PROMPT=$(generate_prompt "$NEXT_DAY" "$TODAY" "$LAST_DAY" "$LAST_TARGET" "$EXTRA_PROMPT" "deepseek")
      run_opencode "$PROMPT" "opencode/deepseek-v4-flash-free" 300 "$TEMP_OUT"
    else
      PROMPT=$(generate_prompt "$NEXT_DAY" "$TODAY" "$LAST_DAY" "$LAST_TARGET" "$EXTRA_PROMPT" "deepseek")
      run_opencode "$PROMPT" "opencode/deepseek-v4-flash-free" 300 "$TEMP_OUT"
    fi
    cat "$TEMP_OUT" >> "$LOG_FILE"
    cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

    CURRENT_DAY=$(check_memory_advance)
    if [ "$CURRENT_DAY" -ge "$NEXT_DAY" ]; then
      info "Tier 1 SUCCESS! Memory advanced to Day $CURRENT_DAY"
      TIER1_FAILED=0
    elif grep -iqE "rate limit|too many requests|429|quota exceeded|free usage exceeded|subscribe|API key|apikey|invalid" "$TEMP_OUT" 2>/dev/null; then
      warn "Tier 1 rate-limited or failed. Progressing to Tier 2..."
    else
      warn "Tier 1 did not advance memory. Progressing to Tier 2..."
    fi
    rm -f "$TEMP_OUT"

    # Tier 2: Google Gemini fallback
    TIER2_FAILED=1
    if [ "$TIER1_FAILED" -eq 1 ] && [ "$GEMINI_AVAILABLE" -eq 1 ]; then
      info "[Model Tier 2/3] Attempting Google Gemini..."
      git reset --hard HEAD >> "$LOG_FILE" 2>&1
      git clean -fd >> "$LOG_FILE" 2>&1

      pkill -9 -f "opencode.*$PROJECT_DIR" 2>/dev/null || true
      sleep 2

      TEMP_OUT=$(mktemp)
      PROMPT=$(generate_prompt "$NEXT_DAY" "$TODAY" "$LAST_DAY" "$LAST_TARGET" "$EXTRA_PROMPT" "gemini")

      if [ -n "$OPENROUTER_API_KEY" ] && [ -n "$OPENROUTER_MODEL_T2" ]; then
        run_opencode "$PROMPT" "openrouter/$OPENROUTER_MODEL_T2" 300 "$TEMP_OUT"
      else
        run_opencode "$PROMPT" "google/gemini-2.5-flash" 300 "$TEMP_OUT"
      fi
      cat "$TEMP_OUT" >> "$LOG_FILE"
      cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

      CURRENT_DAY=$(check_memory_advance)
      if [ "$CURRENT_DAY" -ge "$NEXT_DAY" ]; then
        info "Tier 2 SUCCESS! Memory advanced to Day $CURRENT_DAY"
        TIER2_FAILED=0
      elif grep -iqE "rate limit|too many requests|429|quota exceeded|resource exhausted|API key|apikey|invalid" "$TEMP_OUT" 2>/dev/null; then
        warn "Tier 2 rate-limited or failed. Progressing to Tier 3..."
      else
        warn "Tier 2 did not advance memory. Progressing to Tier 3..."
      fi
      rm -f "$TEMP_OUT"
    fi

    # Tier 3: Local Ollama (offline, unlimited)
    TIER3_FAILED=1
    if [ "$TIER1_FAILED" -eq 1 ] && [ "$TIER2_FAILED" -eq 1 ] && [ "$OLLAMA_AVAILABLE" -eq 1 ]; then
      info "[Model Tier 3/3] Attempting local Ollama (offline, unlimited)..."
      ollama serve > /dev/null 2>&1 &
      sleep 2

      for ((OLLAMA_ATTEMPT=1; OLLAMA_ATTEMPT<=10; OLLAMA_ATTEMPT++)); do
        info "Ollama sub-attempt $OLLAMA_ATTEMPT/10..."

        git reset --hard HEAD >> "$LOG_FILE" 2>&1
        git clean -fd >> "$LOG_FILE" 2>&1
        git fetch origin >> "$LOG_FILE" 2>&1
        git checkout main >> "$LOG_FILE" 2>&1
        git pull origin main >> "$LOG_FILE" 2>&1

        TEMP_OUT=$(mktemp)
        PROMPT=$(generate_prompt "$NEXT_DAY" "$TODAY" "$LAST_DAY" "$LAST_TARGET" "$EXTRA_PROMPT" "ollama")
        run_opencode "$PROMPT" "ollama-local/qwen3.5-coder:9b" 600 "$TEMP_OUT"
        cat "$TEMP_OUT" >> "$LOG_FILE"
        cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true
        rm -f "$TEMP_OUT"

        CURRENT_DAY=$(check_memory_advance)
        if [ "$CURRENT_DAY" -ge "$NEXT_DAY" ]; then
          info "Tier 3 SUCCESS! Memory advanced to Day $CURRENT_DAY"
          TIER3_FAILED=0
          break
        else
          warn "Ollama sub-attempt $OLLAMA_ATTEMPT did not merge. Retrying..."
          sleep 20
        fi
      done
    fi

    # ── Tri-fail wind down ──────────────────────────────────────────────────────
    if [ "$TIER1_FAILED" -eq 1 ] && [ "$TIER2_FAILED" -eq 1 ] && { [ "$TIER3_FAILED" -eq 1 ] || [ "$OLLAMA_AVAILABLE" -eq 0 ]; }; then
      git reset --hard HEAD >> "$LOG_FILE" 2>&1
      git clean -fd >> "$LOG_FILE" 2>&1
      warn "All 3 developer engines failed or were unavailable on attempt $ATTEMPT."
      warn "System state locked (network/API limits). Exiting."
      cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true
      exit 0
    fi

    # ── Check merge success ────────────────────────────────────────────────────
    git pull origin main >> "$LOG_FILE" 2>&1
    FINAL_DAY=$(get_last_day)
    FINAL_DAY=${FINAL_DAY:-0}

    if [ "$FINAL_DAY" -ge "$NEXT_DAY" ]; then
      ok "Day $NEXT_DAY SUCCESS on attempt $ATTEMPT (Memory now at Day $FINAL_DAY)"
      cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true
      break
    else
      warn "Attempt $ATTEMPT did not result in merge. Retrying in ${RETRY_DELAY}s..."
      cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true

      git fetch origin >> "$LOG_FILE" 2>&1
      git checkout main >> "$LOG_FILE" 2>&1
      git pull origin main >> "$LOG_FILE" 2>&1

      if [ "$ATTEMPT" -lt "$MAX_RETRIES" ]; then
        sleep "$RETRY_DELAY"
      else
        fail "Day $NEXT_DAY FAILED after $MAX_RETRIES attempts"
      fi
    fi
  done

  FINAL_DAY=$(get_last_day)
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DONE] Day $NEXT_DAY cycle complete (Memory: Day $FINAL_DAY)" >> "$LOG_FILE"

  # ── Session Cleanup ──────────────────────────────────────────────────────────
  SESSION_DIR="$HOME/.local/share/opencode/storage/session_diff"
  if [ -d "$SESSION_DIR" ]; then
    ls -t "$SESSION_DIR"/ses_*.json 2>/dev/null | tail -n +2 | while read -r OLD_SESSION; do
      rm -f "$OLD_SESSION"
      info "Cleaned up old session: $(basename "$OLD_SESSION")"
    done 2>/dev/null || true
  fi

  echo "" >> "$LOG_FILE"
  cp "$LOG_FILE" "$PROJECT_DIR/.cronbuild.log" 2>/dev/null || true
}

main "$@"
