# get

The one-line bootstrap for a new Skyflow developer machine. Paste the line
for your platform into a terminal; it installs the few tools needed to reach
the [Skyflow developer hub](https://github.com/Skyflow-Network/skyflow-developer-hub),
signs you in to GitHub, clones the hub, and hands off to the hub's
`setup.sh`, which does everything else.

**macOS** (Terminal app):

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Skyflow-Network/get/main/install.sh)"
```

**Windows** (PowerShell):

```powershell
irm https://raw.githubusercontent.com/Skyflow-Network/get/main/install.ps1 | iex
```

**Linux** uses the macOS line. It installs git and the GitHub CLI, signs you
in, clones the hub, and then stops with a clear message, because the hub's
`setup.sh` supports macOS only for now. The Windows script stops at the same
point for the same reason.

## Why this repo is public

The hub is private, so a script inside it cannot be fetched by someone who
is not signed in to GitHub yet, which is exactly the situation the bootstrap
solves. This repository holds only the two bootstrap scripts and nothing
else: no credentials, no internal URLs beyond the hub's name. You still need
an invitation to the Skyflow-Network org for the clone step to work.

## What the scripts do

1. Print what they are about to do.
2. Install only what is needed to reach `setup.sh`:
   macOS installs Homebrew (which brings the Xcode Command Line Tools) and
   the GitHub CLI; Linux installs git with the package manager and the
   GitHub CLI into `~/.local/bin`; Windows installs Git for Windows and the
   GitHub CLI with winget.
3. Run `gh auth login --web` if you are not signed in. If sign-in fails or
   is cancelled, they stop before touching anything else.
4. Clone the hub, pinned to `main`, into `~/skyflow/skyflow-developer-hub`
   (`%USERPROFILE%\skyflow\skyflow-developer-hub` on Windows). If it is
   already there, it must really be the hub (origin on github.com), and it is
   fast-forwarded only when the checkout is on `main`; otherwise the script
   says so and carries on. A failed or interrupted clone leaves no directory
   behind.
5. macOS: `exec ./setup.sh`, so its exit code is the script's exit code.
   Linux and Windows: stop with exit code 2 and name who to contact.

Re-running on a set-up machine fast-forwards the hub (clean checkout on
`main`) and re-runs `setup.sh`.

## Options

- `SKYFLOW_HUB_DIR` changes where the hub is cloned.
- Arguments after the macOS line go to `setup.sh`, for example
  `bash -c "$(curl -fsSL .../install.sh)" -- doctor`. The `--` fills bash's
  `$0` slot so that `doctor` arrives as the first real argument.

## Changing the scripts

Every change goes through a pull request; CI runs `shellcheck` on
`install.sh` and the PowerShell parser plus PSScriptAnalyzer on
`install.ps1`. The rules for the scripts live in the hub's
`docs/decisions/0001-public-bootstrap-home.md`: US English only, pin the
hub clone to `main`, never use `sudo` beyond what the platform's own
installers prompt for, and install nothing that `setup.sh` already installs.
