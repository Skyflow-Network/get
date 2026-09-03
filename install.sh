#!/bin/bash
#
# Skyflow one-line bootstrap for macOS and Linux.
#
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/Skyflow-Network/get/main/install.sh)"
#
# Takes a machine from "nothing installed" to "skyflow-developer-hub cloned
# and ./setup.sh running". It installs only what is needed to get there:
#
#   macOS   Homebrew (its installer also installs the Xcode Command Line
#           Tools; that is the only step that asks for your password), then
#           the GitHub CLI (gh). git ships with the Command Line Tools.
#   Linux   git via your package manager (asks for your password), then the
#           GitHub CLI as a release tarball in ~/.local/bin (no sudo).
#
# Then it signs you in to GitHub (a browser window opens), clones the hub to
# ~/skyflow/skyflow-developer-hub — or pulls it if it is already there — and
# on macOS hands off to ./setup.sh, which installs everything else and
# whose exit code becomes this script's exit code.
#
# setup.sh supports macOS only for now. On Linux this script stops after
# cloning the hub and tells you who to contact (exit code 2).
#
# Safe to run again anytime. Any arguments are passed through to setup.sh.
#
# Environment:
#   SKYFLOW_HUB_DIR   where the hub is cloned (default: ~/skyflow/skyflow-developer-hub)
#
set -u

HUB_REPO="Skyflow-Network/skyflow-developer-hub"
HUB_BRANCH="main"
HUB_DIR="${SKYFLOW_HUB_DIR:-$HOME/skyflow/skyflow-developer-hub}"
CONTACT="the platform owner (Ish, GitHub @dev-z; see CLAUDE.md in the hub)"

BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
YLW=$(printf '\033[33m'); NC=$(printf '\033[0m')
say()   { printf '%s\n' "$*"; }
ok()    { printf '  %s✓%s %s\n' "$GRN" "$NC" "$*"; }
warn()  { printf '  %s!%s %s\n' "$YLW" "$NC" "$*"; }
err()   { printf '  %s✗%s %s\n' "$RED" "$NC" "$*"; }
head_() { printf '\n%s%s%s\n' "$BOLD" "$*" "$NC"; }
die()   { err "$*"; exit 1; }
have()  { command -v "$1" >/dev/null 2>&1; }

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *) die "Unsupported operating system: $(uname -s). This script supports macOS and Linux; Windows uses install.ps1." ;;
esac

# A clone that is interrupted (Ctrl-C) or fails must not leave a half-cloned
# directory behind: CLEANUP_DIR is set only while the clone is in progress.
CLEANUP_DIR=""
trap '[ -n "$CLEANUP_DIR" ] && rm -rf "$CLEANUP_DIR"' EXIT
trap 'printf "\n"; err "Cancelled. Nothing was cloned; run this command again to retry."; exit 130' INT TERM

# ── what this will do ────────────────────────────────────────────────────
head_ "Skyflow bootstrap"
say "This script will:"
if [ "$PLATFORM" = macos ]; then
  say "  1. install Homebrew if it is missing (press Enter when it asks, then type your Mac password)"
  say "  2. install the GitHub CLI (gh)"
else
  say "  1. install git if it is missing (your package manager will ask for your password)"
  say "  2. install the GitHub CLI (gh) into ~/.local/bin"
fi
say "  3. sign you in to GitHub (a browser window opens)"
say "  4. clone the Skyflow developer hub into $HUB_DIR (or pull it if it is already there)"
if [ "$PLATFORM" = macos ]; then
  say "  5. run the hub's ./setup.sh, which installs everything else"
else
  say "  5. stop: the hub's setup.sh supports macOS only for now"
fi

# ── step 1 + 2: the tools needed to reach setup.sh ───────────────────────
load_brew() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && { eval "$("$b" shellenv)"; return 0; }
  done
  have brew
}

# Download fully, sanity-check, THEN execute. Never pipe the network straight
# into bash: a truncated transfer must not run half a script.
fetch_script() { # fetch_script <url> <dest>
  curl -fsSL "$1" -o "$2" && [ -s "$2" ] && head -1 "$2" | grep -q '^#!'
}

install_gh_linux() {
  api="https://api.github.com/repos/cli/cli/releases/latest"
  version="$(curl -fsSL "$api" | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')"
  [ -n "$version" ] || die "could not find the latest GitHub CLI release. Check your internet connection and run this command again."
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "unsupported CPU architecture: $(uname -m)" ;;
  esac
  tarball="gh_${version}_linux_${arch}.tar.gz"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/skyflow-gh.XXXXXX")"
  curl -fsSL "https://github.com/cli/cli/releases/download/v${version}/${tarball}" -o "$tmp/$tarball" \
    || { rm -rf "$tmp"; die "could not download the GitHub CLI ($tarball)."; }
  tar -xzf "$tmp/$tarball" -C "$tmp" || { rm -rf "$tmp"; die "could not unpack the GitHub CLI."; }
  mkdir -p "$HOME/.local/bin"
  cp "$tmp/gh_${version}_linux_${arch}/bin/gh" "$HOME/.local/bin/gh" || { rm -rf "$tmp"; die "could not install gh into ~/.local/bin."; }
  chmod +x "$HOME/.local/bin/gh"
  rm -rf "$tmp"
  export PATH="$HOME/.local/bin:$PATH"
  # Make gh available in the user's next terminal too, not only in this run.
  profile="$HOME/.profile"
  # The line is meant to expand when the profile is sourced, not now.
  # shellcheck disable=SC2016
  line='export PATH="$HOME/.local/bin:$PATH"'
  touch "$profile"
  grep -qxF "$line" "$profile" || printf '\n# Added by the Skyflow bootstrap (GitHub CLI)\n%s\n' "$line" >> "$profile"
}

head_ "Tools"
if [ "$PLATFORM" = macos ]; then
  if load_brew; then ok "Homebrew"; else
    warn "Homebrew is missing; installing it (this also installs the Xcode Command Line Tools)..."
    inst="$(mktemp "${TMPDIR:-/tmp}/skyflow-brew.XXXXXX")"
    fetch_script https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh "$inst" \
      || { rm -f "$inst"; die "could not download the Homebrew installer. Check your internet connection and run this command again."; }
    /bin/bash "$inst"; brew_status=$?
    rm -f "$inst"
    [ "$brew_status" = 0 ] || die "Homebrew install did not complete. Run this command again to retry (see https://brew.sh if it keeps failing)."
    load_brew || die "Homebrew was installed but 'brew' was not found. Open a new terminal and run this command again."
    ok "Homebrew installed"
  fi
  if xcode-select -p >/dev/null 2>&1; then ok "Xcode Command Line Tools"; else
    warn "Xcode Command Line Tools missing; a dialog will pop up. Click Install, wait for it to finish, then run this command again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
  fi
  ok "git"
  if have gh; then ok "GitHub CLI"; else
    warn "GitHub CLI is missing; installing it with Homebrew..."
    brew install gh >/dev/null 2>&1 || die "could not install the GitHub CLI. Run: brew install gh, then run this command again."
    ok "GitHub CLI installed"
  fi
else
  if have git; then ok "git"; else
    warn "git is missing; installing it with your package manager (you may be asked for your password)..."
    if have apt-get; then sudo apt-get update -qq && sudo apt-get install -y -qq git
    elif have dnf; then sudo dnf install -y -q git
    elif have pacman; then sudo pacman -S --noconfirm --needed git
    else die "could not find apt-get, dnf, or pacman. Install git yourself, then run this command again."
    fi
    have git || die "git install did not complete. Run this command again to retry."
    ok "git installed"
  fi
  export PATH="$HOME/.local/bin:$PATH"
  if have gh; then ok "GitHub CLI"; else
    warn "GitHub CLI is missing; installing the latest release into ~/.local/bin..."
    install_gh_linux
    have gh || die "GitHub CLI install did not complete. Run this command again to retry."
    ok "GitHub CLI installed"
  fi
fi

# ── step 3: GitHub sign-in ───────────────────────────────────────────────
head_ "GitHub sign-in"
if gh auth status >/dev/null 2>&1; then
  ok "signed in as $(gh api user -q .login 2>/dev/null || echo '?')"
else
  warn "A browser window will open. Sign in with the GitHub account that was invited to Skyflow-Network."
  gh auth login --hostname github.com --web --git-protocol https \
    || die "GitHub sign-in did not complete. Nothing was changed on your machine; run this command again to retry."
  ok "signed in as $(gh api user -q .login 2>/dev/null || echo '?')"
fi
gh repo view "$HUB_REPO" --json name >/dev/null 2>&1 \
  || die "Your GitHub account cannot see $HUB_REPO. Ask $CONTACT to invite you to the Skyflow-Network org, accept the invitation email, then run this command again."

# ── step 4: the hub ──────────────────────────────────────────────────────
head_ "Skyflow developer hub"
if [ -d "$HUB_DIR/.git" ]; then
  ok "already cloned at $HUB_DIR"
  if git -C "$HUB_DIR" pull --ff-only --quiet origin "$HUB_BRANCH" >/dev/null 2>&1; then ok "pulled the latest $HUB_BRANCH"; else
    warn "could not pull (local changes or a different branch?); continuing with the checkout as it is"
  fi
elif [ -e "$HUB_DIR" ]; then
  die "$HUB_DIR exists but is not a git checkout. Move it away, then run this command again."
else
  mkdir -p "$(dirname "$HUB_DIR")" || die "could not create $(dirname "$HUB_DIR")"
  CLEANUP_DIR="$HUB_DIR"
  gh repo clone "$HUB_REPO" "$HUB_DIR" -- --branch "$HUB_BRANCH" --quiet \
    || die "clone failed. Nothing was left behind; run this command again to retry."
  CLEANUP_DIR=""
  ok "cloned into $HUB_DIR"
fi
[ -x "$HUB_DIR/setup.sh" ] || die "$HUB_DIR/setup.sh is missing or not executable. Ask $CONTACT for help."

# ── step 5: hand off ─────────────────────────────────────────────────────
if [ "$PLATFORM" = macos ]; then
  head_ "Handing off to setup.sh"
  say "  Everything from here on is $HUB_DIR/setup.sh; run it again anytime with the same one-line command."
  cd "$HUB_DIR" || die "could not enter $HUB_DIR"
  exec ./setup.sh "$@"
fi

head_ "Stopping here"
err "The hub's setup.sh supports macOS only for now, so this script cannot finish setting up a Linux machine."
say "  The hub is cloned at $HUB_DIR and you are signed in to GitHub."
say "  Ask $CONTACT to finish setting up your machine."
exit 2
