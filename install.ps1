<#
Skyflow one-line bootstrap for Windows.

    irm https://raw.githubusercontent.com/Skyflow-Network/get/main/install.ps1 | iex

Installs Git for Windows and the GitHub CLI (gh) with winget, signs you in
to GitHub (a browser window opens), and clones the Skyflow developer hub to
%USERPROFILE%\skyflow\skyflow-developer-hub (or pulls it if it is already
there). Then it stops: the hub's setup.sh supports macOS only for now, and
this script says so instead of pretending. Run as a file
(powershell -File install.ps1) it exits with code 2 at that point; piped
into iex it ends the script without closing your window.

Safe to run again anytime.

Environment:
    SKYFLOW_HUB_DIR   where the hub is cloned (default: %USERPROFILE%\skyflow\skyflow-developer-hub)
#>

# Write-Host is deliberate: this is an interactive installer whose colored
# console output is the point, and Write-Output would leak into the pipeline
# when the script is piped into iex.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive installer; Write-Output would leak into the iex pipeline')]
param()

$HubRepo = 'Skyflow-Network/skyflow-developer-hub'
$HubBranch = 'main'
$HubDir = if ($env:SKYFLOW_HUB_DIR) { $env:SKYFLOW_HUB_DIR } else { Join-Path $HOME 'skyflow\skyflow-developer-hub' }
$Contact = 'the platform owner (Ish, GitHub @dev-z; see CLAUDE.md in the hub)'
# 'exit' inside a script piped into iex closes the user's PowerShell window,
# so a script started that way stops with 'break' instead (scoop does the same).
$RunAsFile = [bool]$PSCommandPath

function Say($Text) { Write-Host $Text }
function Ok($Text) { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Warn($Text) { Write-Host "  [!]  $Text" -ForegroundColor Yellow }
function Err($Text) { Write-Host "  [x]  $Text" -ForegroundColor Red }
function Head($Text) { Write-Host ''; Write-Host $Text -ForegroundColor Cyan }
function Have($Command) { [bool](Get-Command $Command -ErrorAction SilentlyContinue) }
function Exit-Bootstrap($Code) { if ($RunAsFile) { exit $Code } else { break } }
function Fail($Text) { Err $Text; Exit-Bootstrap 1 }
# winget installs land on the machine PATH; pick them up without a new window.
function Sync-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Install-WithWinget($Id, $Name) {
    Warn "$Name is missing; installing it with winget (Windows may ask you to allow the installer)..."
    winget install --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "could not install $Name (winget exit code $LASTEXITCODE). Run: winget install --id $Id, then run this command again." }
    Sync-Path
}

# -- what this will do ------------------------------------------------------
Head 'Skyflow bootstrap'
Say 'This script will:'
Say '  1. install Git for Windows and the GitHub CLI (gh) with winget, if they are missing'
Say '  2. sign you in to GitHub (a browser window opens)'
Say "  3. clone the Skyflow developer hub into $HubDir (or pull it if it is already there)"
Say "  4. stop: the hub's setup.sh supports macOS only for now"

# -- step 1: tools ------------------------------------------------------------
Head 'Tools'
if (-not (Have 'winget')) {
    Fail "winget is missing. Install 'App Installer' from the Microsoft Store (it provides winget), then run this command again."
}
if (Have 'git') { Ok 'git' } else { Install-WithWinget 'Git.Git' 'Git for Windows'; if (Have 'git') { Ok 'git installed' } else { Fail 'Git was installed but is not on your PATH yet. Open a new PowerShell window and run this command again.' } }
if (Have 'gh') { Ok 'GitHub CLI' } else { Install-WithWinget 'GitHub.cli' 'GitHub CLI'; if (Have 'gh') { Ok 'GitHub CLI installed' } else { Fail 'The GitHub CLI was installed but is not on your PATH yet. Open a new PowerShell window and run this command again.' } }

# -- step 2: GitHub sign-in ---------------------------------------------------
Head 'GitHub sign-in'
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Ok "signed in as $(gh api user -q .login 2>$null)"
} else {
    Warn 'A browser window will open. Sign in with the GitHub account that was invited to Skyflow-Network.'
    gh auth login --hostname github.com --web --git-protocol https
    if ($LASTEXITCODE -ne 0) { Fail 'GitHub sign-in did not complete. Nothing was changed on your machine; run this command again to retry.' }
    Ok "signed in as $(gh api user -q .login 2>$null)"
}
gh repo view $HubRepo --json name 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "Your GitHub account cannot see $HubRepo. Ask $Contact to invite you to the Skyflow-Network org, accept the invitation email, then run this command again."
}

# -- step 3: the hub ----------------------------------------------------------
Head 'Skyflow developer hub'
if (Test-Path (Join-Path $HubDir '.git')) {
    # The checkout at $HubDir must really be the hub, not some other repo.
    $origin = git -C $HubDir remote get-url origin 2>$null
    if (-not ($origin -match '(?i)github\.com[:/]skyflow-network/skyflow-developer-hub(\.git)?$')) {
        Fail "$HubDir is a git checkout of something other than $HubRepo. Move it away or set SKYFLOW_HUB_DIR to a different path, then run this command again."
    }
    Ok "already cloned at $HubDir"
    $branch = git -C $HubDir rev-parse --abbrev-ref HEAD 2>$null
    if ($branch -ne $HubBranch) {
        Warn "the hub is on branch '$branch', not '$HubBranch'; not pulling (switch back to $HubBranch yourself if you want updates)"
    } else {
        git -C $HubDir pull --ff-only --quiet origin $HubBranch 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Ok "pulled the latest $HubBranch" } else { Warn 'could not pull (local changes?); continuing with the checkout as it is' }
    }
} elseif (Test-Path $HubDir) {
    Fail "$HubDir exists but is not a git checkout. Move it away, then run this command again."
} else {
    $parent = Split-Path $HubDir -Parent
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    # Clone into a temporary directory next to the target and move it into
    # place only when done: a failed clone removes only that temporary
    # directory, and two runs at once cannot delete each other's work.
    $tmp = Join-Path $parent ('.skyflow-developer-hub.' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    gh repo clone $HubRepo $tmp -- --branch $HubBranch --quiet
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        Fail 'clone failed. Nothing was left behind; run this command again to retry.'
    }
    if (Test-Path $HubDir) {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        Fail "$HubDir appeared while cloning (another run?). Run this command again."
    }
    Move-Item -Path $tmp -Destination $HubDir
    # If the target appeared between the check and the move, Move-Item put the
    # clone inside it instead of at it: remove only our clone, leave the other.
    $nested = Join-Path $HubDir (Split-Path $tmp -Leaf)
    if (Test-Path $nested) {
        Remove-Item -Recurse -Force $nested -ErrorAction SilentlyContinue
        Fail "$HubDir appeared while cloning (another run?). Run this command again."
    }
    Ok "cloned into $HubDir"
}

# -- step 4: stop honestly ----------------------------------------------------
Head 'Stopping here'
Err "The hub's setup.sh supports macOS only for now, so this script cannot finish setting up a Windows machine."
Say "  The hub is cloned at $HubDir and you are signed in to GitHub."
Say "  Ask $Contact to finish setting up your machine."
Exit-Bootstrap 2
