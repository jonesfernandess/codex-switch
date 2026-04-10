<div align="center">

# Codex Switch

**Run your work and personal Codex CLI accounts side by side.**

One machine. Multiple logins. Zero friction. Auto-switches on quota.

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-brightgreen.svg)]()
[![Linux](https://img.shields.io/badge/Linux-supported-brightgreen.svg)]()
[![Codex CLI](https://img.shields.io/badge/Codex%20CLI-v0.118+-blueviolet.svg)](https://github.com/openai/codex)

</div>

---

## The Problem

Codex CLI stores one login per machine. If you have a **work account** and a **personal account**, you have to log out and log in every time you switch. That gets old fast. And when you hit a quota limit mid-session, you're stuck.

## The Fix

```bash
codex-switch work        # launches Codex with your work account
codex-switch personal    # launches Codex with your personal account
codex-switch auto        # rotates accounts automatically
```

Both can run in separate terminals, simultaneously. Hit a quota? Switch is instant.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SaschaHeyer/codex-switch/main/install.sh | sh
```

Or with Homebrew:

```bash
brew install gum  # required dependency
curl -fsSL https://raw.githubusercontent.com/SaschaHeyer/codex-switch/main/install.sh | sh
```

<details>
<summary><strong>Manual install</strong></summary>

```bash
# Download
curl -fsSL https://raw.githubusercontent.com/SaschaHeyer/codex-switch/main/codex-switch \
  -o ~/.local/bin/codex-switch

# Make executable
chmod +x ~/.local/bin/codex-switch

# Install gum for interactive UI
brew install gum
```

</details>

<details>
<summary><strong>Uninstall</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/SaschaHeyer/codex-switch/main/install.sh | sh -s -- uninstall
```

</details>

---

## Quick Start

### 1. Create profiles

```bash
codex-switch create work
codex-switch create personal
```

### 2. Launch Codex with a profile

```bash
codex-switch work
```

Codex opens with that profile's account. On first launch, it'll ask you to log in — you only do this once per profile.

### 3. Run both side by side

Open two terminals:

```
Terminal 1                    Terminal 2
$ codex-switch work           $ codex-switch personal
```

Each runs with its own auth session, history, and usage tracking. Your rules, skills, and AGENTS.md are shared across all profiles.

---

## Auto-Switch on Quota

When you hit a rate limit or quota, codex-switch can switch to the next account automatically.

### Interactive sessions

```bash
codex-switch auto
```

Picks the next profile in rotation on each call. If Codex exits with an error, prompts you to retry with the next profile immediately.

### Non-interactive sessions

```bash
codex-switch auto exec "refactor this function"
```

Captures stderr, detects quota/rate-limit errors (`429`, `rate limit exceeded`, `quota exceeded`, etc.), switches to the next profile, and retries — all without intervention. Tries every profile before giving up.

### Manual rotation

```bash
codex-switch next   # advance to the next profile manually
```

### Make every `codex` call auto-switch

During install, you'll be prompted:

```
  Optional: make every codex call auto-switch accounts.
  This will add the following line to ~/.zshrc:

    alias codex='codex-switch auto'

  Any time you run 'codex', it will automatically use the next
  profile in rotation and retry on quota/rate-limit errors.

  Add this alias? [y/N]
```

If you accept, every `codex` call goes through auto-switch transparently. You can always add it manually later:

```bash
echo "alias codex='codex-switch auto'" >> ~/.zshrc
source ~/.zshrc
```

---

## When is auto useful?

### 1. You have multiple accounts and want to spread usage

Each call to `codex-switch auto` picks the next profile in rotation automatically — no thinking, no choosing.

```
1st session → default  (personal account)
2nd session → work     (company account)
3rd session → client   (client account)
4th session → default  ← wraps around
```

Useful when you pay per usage and want to distribute cost across accounts, or when each account has its own monthly limit.

### 2. You hit a quota in the middle of an exec

```bash
codex-switch auto exec "refactor the entire service layer"
```

If the current account returns a 429 or "quota exceeded", auto-switch moves to the next one and retries the same prompt — silently, without any intervention.

### 3. Scripts and automations that can't stop

```bash
for task in tasks/*.md; do
  codex-switch auto exec "$(cat $task)"
done
```

Auto-switch ensures the script doesn't stall on a quota error. It cycles through every available account before giving up.

### 4. Interactive session that closed with an error

If a TUI session exits with a non-zero code (quota, expired token, etc.), the terminal asks:

```
! Codex exited with error (code 1).
? Retry with next profile (work)? [Yes, switch / No, exit]
```

One `y` and you're back in, on a different account, without retyping anything.

### What it does NOT solve

- Cannot detect quota **inside** an active TUI session — Codex owns the terminal, there's no way to intercept
- Makes no difference with a single account — requires 2+ profiles to be useful

---

## Commands

| Command | Description |
|---------|-------------|
| `codex-switch <name>` | Launch Codex with that profile |
| `codex-switch create [name]` | Create a new profile |
| `codex-switch list` | Show all profiles and login status |
| `codex-switch delete [name]` | Delete a profile |
| `codex-switch auto [args...]` | Launch with automatic account rotation |
| `codex-switch next` | Manually advance to the next profile |
| `codex-switch` | Interactive menu |
| `codex-switch help` | Show help |

---

## How It Works

Codex CLI reads its config from `~/.codex/`. Codex Switch creates separate directories (`~/.codex-work/`, `~/.codex-personal/`) and tells Codex which one to use via `CODEX_HOME`.

```
~/.codex/              ← default profile
~/.codex-work/         ← work profile
~/.codex-personal/     ← personal profile
```

**Shared** across profiles (via symlinks):
- `rules/` — your custom rules
- `skills/` — your custom skills
- `AGENTS.md` — global agent instructions

**Isolated** per profile:
- `auth.json` — OAuth tokens or API key
- `sessions/` — session history
- `memories/` — AI memories
- Usage tracking

Auto-switch rotation state is stored in `~/.codex-switch-auto`.

---

## Requirements

- [Codex CLI](https://github.com/openai/codex) v0.118+
- [gum](https://github.com/charmbracelet/gum) (auto-installed via Homebrew if missing)
- macOS or Linux
- bash 3.2+

---

## Credits

This project is a fork of [claude-switch](https://github.com/SaschaHeyer/claude-switch) by [Sascha Heyer](https://github.com/SaschaHeyer).

The original tool solved the same problem for Claude Code — multiple accounts on one machine with zero friction. All the core architecture (profile directories, symlinked shared config, gum-based UI, alias management) comes from his work.

This fork ports it to the Codex CLI and adds automatic account rotation on quota/rate-limit errors.

Thank you, Sascha. Great idea, great execution.

---

## License

MIT

---

<div align="center">

**Codex Switch** is not affiliated with OpenAI.

</div>
