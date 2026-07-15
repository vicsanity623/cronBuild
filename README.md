# 🏗️ CRONBUILD — Autonomous AI Development Pipeline

> **Build any software project. Automatically. On a schedule.**
> Your codebase that codes itself — one PR at a time, every cycle.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 📋 What is CRONBUILD?

CRONBUILD is a **fully autonomous software development engine** that uses AI agents to continuously build, improve, and maintain your codebase on a recurring schedule. It is a single bash script that orchestrates the entire development lifecycle:

1. **Reads** your project's state from `MEMORY.md`
2. **Increments** the development day counter
3. **Launches** an AI coding agent (via [opencode](https://opencode.ai)) with full project context
4. **The agent** implements features, creates Git branches, opens Pull Requests, and merges them
5. **Updates** `MEMORY.md` with what was built and what to build next
6. **Retries** on failure — guaranteeing forward progress through a 3-tier model cascade
7. **Compacts** memory when it grows too large to prevent context window overflow

### One-Click Operation

```
./setup.sh → enter API key → done. Your project builds itself forever.
```

---

## 🔄 How It Works

```
                    ┌─────────────────────────────────┐
                    │         CRON TRIGGERED           │
                    │   (every hour / daily / custom)  │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │      READ MEMORY.md              │
                    │   "Day 3 completed. Next: Guild" │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │     LAUNCH OPENCODE AGENT         │
                    │  With Day 4's target + full ctx   │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │   AGENT: IMPLEMENT & PR          │
                    │  1. Read project files           │
                    │  2. Implement feature            │
                    │  3. git branch → commit → push   │
                    │  4. gh pr create                 │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │   AGENT: MERGE & UPDATE LOG      │
                    │  1. gh pr merge --squash         │
                    │  2. Append to MEMORY.md          │
                    │  3. Push to main                 │
                    └──────────────┬──────────────────┘
                                   │
                    ┌──────────────▼──────────────────┐
                    │   VERIFICATION                   │
                    │  Memory advanced? → Done ✅      │
                    │  Failed? → Retry with error ctx  │
                    └──────────────┬──────────────────┘
                                   │
                          WAIT FOR NEXT CRON TICK
```

---

## ✨ What Makes CRONBUILD Powerful

### 🧠 Three-Tier Model Cascade

CRONBUILD never gets stuck. It tries three AI models in sequence:

| Tier | Model | Type | Cost | Best For |
|------|-------|------|------|----------|
| **1** | DeepSeek (or any OpenRouter model) | Cloud API | Paid/Free | Primary development |
| **2** | Google Gemini 2.5 Flash | Cloud API | Paid/Free | Fallback when Tier 1 is rate-limited |
| **3** | Local Ollama (qwen3.5-coder:9b) | Local | Free | Offline/last resort |

If Tier 1 fails (rate limit, API error), Tier 2 kicks in automatically. If both fail, Tier 3 runs on your local machine with **zero API cost** and unlimited calls. Your build cycle **never dies**.

### 🔁 Automatic Retry Loop

Each day gets up to **10 retry attempts**. Each retry:
- Cleans the workspace (`git reset --hard`)
- Pulls latest main
- Retries with a smarter prompt that includes the previous failure context

The agent learns from its mistakes on each retry.

### 🗜️ Memory Compaction

After Day 4, CRONBUILD **automatically compresses** MEMORY.md — preserving the latest state while discarding verbose history. This prevents:
- Context window overflow
- Token waste
- Bloating the prompt with irrelevant history

### 🔒 Concurrency Protection

Lock files prevent overlapping runs. If the previous cycle is still running, the new one exits safely.

---

## 🚀 Quick Start

### Prerequisites

| Tool | Required? | Install |
|------|-----------|---------|
| [opencode](https://opencode.ai) | ✅ **Yes** | `curl -fsSL https://opencode.ai/install.sh \| bash` |
| [GitHub CLI (gh)](https://cli.github.com) | ✅ **Yes** | `brew install gh` or visit [cli.github.com](https://cli.github.com) |
| Git | ✅ **Yes** | `brew install git` |
| Perl | ✅ **Yes** | Pre-installed on macOS/Linux |
| [Ollama](https://ollama.com) | ⬜ Optional | `brew install ollama` — for offline fallback |

### One-Click Setup

```bash
# 1. Clone or initialize your project
git init my-awesome-project
cd my-awesome-project

# 2. Download CRONBUILD
curl -L https://raw.githubusercontent.com/YOUR_USER/cronbuild/main/cronbuild.zip -o cronbuild.zip
unzip cronbuild.zip -d cronbuild
cd cronbuild

# 3. Run setup (interactive, one-time)
./setup.sh

# That's it. Your project now builds itself on schedule.
```

Setup walks you through:
- ✅ Checking dependencies (installs what it can)
- ✅ GitHub authentication (`gh auth login`)
- ✅ API key configuration (OpenRouter, Gemini, DeepSeek)
- ✅ Optional Ollama offline model pull
- ✅ Cron scheduling (hourly to daily)

### Manual Start

```bash
# Run once immediately to test
./autonomous.sh /path/to/your/project

# Or see what's happening
tail -f ~/.cronbuild/cronbuild.log
```

---

## 🔑 API Keys & Model Configuration

### Recommended: OpenRouter (One Key, 200+ Models)

[OpenRouter](https://openrouter.ai) gives you access to every major model with a single API key. This is the **recommended configuration** because it provides the most reliable fallback chain.

```bash
# In ~/.cronbuild/.env:
OPENROUTER_API_KEY="sk-or-v1-xxxxxxxxxxxxxxxx"
OPENROUTER_MODEL="deepseek/deepseek-chat"       # Tier 1 (primary)
OPENROUTER_MODEL_T2="google/gemini-2.5-flash"   # Tier 2 (fallback)
```

### Free Tier: Google Gemini

Google Gemini 2.5 Flash has a **generous free tier** that allows many builds per day.

```bash
GOOGLE_GEMINI_API_KEY="AIzaxxxxxxxxxxxxxxxxxxxx"
```

Get one at [Google AI Studio](https://aistudio.google.com/apikey).

### Free Tier: OpenCode DeepSeek

OpenCode's built-in DeepSeek integration works out of the box with no API key, but has stricter rate limits (~10 requests/day).

### Offline: Local Ollama (Completely Free)

Run `ollama pull qwen3.5-coder:9b` (4.7 GB) for a local coding model that works offline with unlimited usage.

### Pricing Comparison

| Provider | Free Tier | Paid Tier | Rate Limit |
|----------|-----------|-----------|------------|
| **OpenRouter** | ❌ | ~$0.15/task | High |
| **Google Gemini** | 60 req/min | ~$0.03/task | Medium-High |
| **DeepSeek (opencode)** | 10/day | Via OpenRouter | Low |
| **Ollama (local)** | Unlimited | N/A | Unlimited (hardware-bound) |

> **Pro tip:** Combine OpenRouter (paid, high rate limit) + Ollama (free, offline) for maximum uptime.

---

## 📁 Project Structure

```
your-project/
├── MEMORY.md              # [CREATE] Your project's brain — tracks what's built & what's next
├── DIRECTIVES.md          # [CREATE] AI behavior rules for your project
├── cronbuild/
│   ├── autonomous.sh      # The core engine — the only thing cron runs
│   ├── setup.sh           # One-click installer & scheduler
│   ├── uninstall.sh       # Clean removal
│   ├── LICENSE            # MIT License
│   └── README.md          # This file
├── .cronbuild.log         # [AUTO] Generated log, synced each cycle
└── src/                   # Your project files — CRONBUILD builds these
```

### MEMORY.md Format

```markdown
# PROJECT MEMORY LOG
*Format: [DAY X] | [DATE] | [COMPLETED] | [NEXT DAY TARGET]*

[DAY 1] | 2026-07-14 | User authentication system with JWT tokens, login/signup pages, password hashing. | NEXT: Payment Integration — Add Stripe checkout flow with webhook handling, subscription tiers, and pricing page.
[DAY 2] | 2026-07-15 | Payment Integration — Stripe SDK setup, checkout session creation, webhook endpoint, pricing page with 3 tiers, subscription status dashboard. | NEXT: Real-time Notifications — Implement WebSocket-based notification system with in-app toast alerts, notification preferences, and unread badge.
```

### DIRECTIVES.md Format

```markdown
# SYSTEM DIRECTIVES
## 1. PROJECT OVERVIEW
You are building an e-commerce platform with Next.js, Tailwind, and PostgreSQL.
Development must be incremental. Never rewrite everything.

## 2. CUSTOM RULES
- All API routes must have input validation
- Use TypeScript strict mode
- Every PR must include tests
```

---

## ⚙️ Advanced Configuration

### Custom Cron Schedule

```bash
# Edit the crontab directly
crontab -e

# Example: every 6 hours
0 */6 * * * /usr/local/bin/cronbuild /path/to/project >> ~/.cronbuild/cronbuild.log 2>&1
```

### Skip Cron (Run Manually Only)

```bash
# Don't use setup.sh's cron. Just run manually:
./cronbuild/autonomous.sh /path/to/project
```

### Custom OpenRouter Model

Edit `~/.cronbuild/.env`:

```bash
OPENROUTER_API_KEY="sk-or-v1-xxx"
OPENROUTER_MODEL="anthropic/claude-3.5-sonnet"        # Tier 1: Claude
OPENROUTER_MODEL_T2="openai/gpt-4o-mini"               # Tier 2: GPT-4o Mini
```

Any model on [OpenRouter's catalog](https://openrouter.ai/models) works.

### Multiple Projects

CRONBUILD is per-project. Set up separate cron jobs:

```bash
0 */6 * * * /usr/local/bin/cronbuild /path/to/project-a
0 */3 * * * /usr/local/bin/cronbuild /path/to/project-b
```

---

## 📊 Monitoring

```bash
# Watch live progress
tail -f ~/.cronbuild/cronbuild.log

# Or from project directory
tail -f .cronbuild.log

# Check last cycle status
tail -5 ~/.cronbuild/cronbuild.log
```

### Log Output Example

```
========================================
2026-07-14 14:00:00 [START] CRONBUILD autonomous cycle
2026-07-14 14:00:01 [INFO] [DAY 5] Starting autonomous cycle
2026-07-14 14:00:01 [INFO] Previous target: Implement Forge Enhancement System
2026-07-14 14:00:01 [INFO] Attempt 1/10
2026-07-14 14:00:02 [INFO] [Model Tier 1/3] Attempting DeepSeek...
...opencode output...
2026-07-14 14:05:30 [INFO] Tier 1 SUCCESS! Memory advanced to Day 5
2026-07-14 14:05:30 [OK] Day 5 SUCCESS on attempt 1
========================================
```

---

## 🎯 Use Cases

CRONBUILD can autonomously build **any software project**:

| Category | Examples |
|----------|----------|
| **Web Apps** | SaaS platforms, dashboards, e-commerce, social networks |
| **Games** | Browser games, mobile games, game backends |
| **APIs** | REST APIs, GraphQL servers, microservices |
| **CLI Tools** | Terminal applications, dev tools, automation scripts |
| **DevOps** | Infrastructure as Code, deployment pipelines, monitoring |
| **Mobile Apps** | React Native, Flutter (via opencode's mobile support) |
| **AI/ML** | Model training pipelines, data processing, inference servers |
| **Open Source** | Libraries, frameworks, plugins, extensions |
| **Prototypes** | MVP generation, concept validation, rapid iteration |

### Example: Build a Web Game in 2 Weeks

```
Day 1:  Project setup, basic HTML/CSS, game canvas
Day 2:  Player movement, collision detection
Day 3:  Enemy AI, spawning system
Day 4:  Scoring, lives, game over screen
Day 5:  Power-ups, particle effects
Day 6:  Sound effects, music
Day 7:  Leaderboard (local storage)
Day 8:  Mobile responsive design
Day 9:  Settings menu, difficulty levels
Day 10: Achievement system
Day 11: Polish — animations, transitions
Day 12: Performance optimization
Day 13: PWA support (offline, install)
Day 14: Final polish, README, deployment
```

### Example: Build a SaaS Backend in 1 Week

```
Day 1:  Auth system (signup/login/JWT)
Day 2:  User profiles, roles, permissions
Day 3:  CRUD API for core resources
Day 4:  Database migrations, seeding
Day 5:  Email notifications (SendGrid)
Day 6:  Payment integration (Stripe)
Day 7:  Admin dashboard, analytics
Day 8:  Rate limiting, caching, performance
Day 9:  Tests, CI/CD pipeline
Day 10: Documentation, deployment
```

---

## ❓ Troubleshooting

| Problem | Solution |
|---------|----------|
| **Script doesn't run** | Check `opencode` is installed: `which opencode` |
| **"Not a git repository"** | Run `git init && git add . && git commit -m "initial"` |
| **PR merge fails** | Check `gh auth status` — re-authenticate if needed |
| **All 3 tiers fail** | Check internet + API keys in `~/.cronbuild/.env` |
| **Rate limited** | Add a paid API key (OpenRouter) or wait for rate limit reset |
| **Ollama not responding** | `pkill -9 ollama` then `ollama serve` |
| **MEMORY.md grows too large** | CRONBUILD auto-compacts at Day 4+. Or manually reset. |

### Reset Your Project (Start Fresh)

```bash
# Reset MEMORY.md to Day 0
echo '# PROJECT MEMORY LOG
*Format: [DAY X] | [DATE] | [COMPLETED] | [NEXT DAY TARGET]*

[DAY 0] | '$(date +%Y-%m-%d)' | Reset — fresh start. | NEXT: <your first feature>' > MEMORY.md

git add MEMORY.md && git commit -m "reset: fresh start" && git push
```

---

## 🧠 How to Write Great MEMORY.md Targets

The quality of CRONBUILD's output depends on your `NEXT:` target. Good targets are:

| ❌ Bad | ✅ Good |
|--------|---------|
| "Add more features" | "Add user profile page with avatar upload, bio field, and settings form in /app/profile/page.tsx" |
| "Fix bugs" | "Fix login timeout bug — session expires after 5 min instead of 24h in /lib/auth.ts line 42" |
| "Improve UI" | "Add dark mode toggle with localStorage persistence, CSS variables, and system preference detection" |
| "Make it better" | "Add pagination to /api/users endpoint with cursor-based pagination, limit/offset params, and total count" |

**Formula for a perfect target:**
`NEXT: <Feature Name> — <What to build> <Which files> <Expected behavior>`

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────┐
│              launchd / cron                      │
│  Fires every N hours, runs autonomous.sh         │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│              autonomous.sh (Bash)                │
│  Orchestrator: lock → sync → compact → count    │
│  Launch agent → verify merge → cleanup           │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│              opencode run (CLI)                  │
│  Launches AI model with crafted prompt           │
│  AI has tool access (bash, write, edit, git, gh) │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│              AI Agent (Model)                    │
│  1. Reads MEMORY.md, DIRECTIVES.md               │
│  2. Implements feature                           │
│  3. git add/commit/push                          │
│  4. gh pr create/merge                           │
│  5. Updates MEMORY.md                            │
└─────────────────────────────────────────────────┘
```

---

## 📜 License

MIT — Free for personal and commercial use. Go build something awesome.

---

## 🙌 Contributing

PRs welcome! The best way to contribute is to let CRONBUILD build itself:
fork, add `cronbuild/` to your fork, set your own `NEXT:` target for improvements.

---

## ⚡ Inspiration

CRONBUILD was born from the idea that **software should build itself incrementally, one verified PR at a time**. Like [Odysseus](https://github.com/odysseus) or [Noclaw](https://github.com/noclaw) setups, it's designed to be a **set-and-forget autonomous development pipeline**.

The core loop — **Read → Implement → PR → Merge → Log → Repeat** — is inspired by how human development teams work, automated entirely through AI agents with a resilient multi-model fallback chain.

> *"The best code is the code that writes itself while you sleep."*
