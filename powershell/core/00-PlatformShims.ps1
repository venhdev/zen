# Cross-platform shims for Windows PowerShell (clip, open, zen, sudo)

# Detect Windows Host Environment (supports both PowerShell 5.1 Desktop and PowerShell Core 7+)
$global:IsWindowsHost = ($PSEdition -eq 'Desktop') -or [bool]$IsWindows

# Clipboard Helper
function clip {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [psobject]$InputObject
    )
    begin {
        $piped = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($null -ne $InputObject) {
            $piped.Add([string]$InputObject)
        }
    }
    end {
        if ($piped.Count -gt 0) {
            Set-Clipboard -Value ($piped -join [Environment]::NewLine)
        } elseif ($args) {
            Set-Clipboard -Value ($args -join ' ')
        } else {
            Get-Clipboard
        }
    }
}

# Open Target (Explorer / Default App)
function open_target {
    param(
        [string]$Target = "."
    )
    if (Test-Path $Target) {
        Invoke-Item $Target
    } else {
        Start-Process $Target
    }
}

function _zen_sync {
    param([string[]]$Arguments = @())

    if ($Arguments -contains "-h" -or $Arguments -contains "--help") {
        Write-Host @"
Usage: zen sync [OPTIONS]

Pull latest commits from remote and reload dotfiles aliases and functions.

Options:
  -h, --help    Show this help message

Note: To reconfigure system modules or run full provisioning, use 'zen setup'.
"@
        return
    }

    $dotfilesRoot = if ($global:DOTFILES_DIR -and (Test-Path $global:DOTFILES_DIR)) {
        $global:DOTFILES_DIR
    } elseif (Test-Path "$env:USERPROFILE\.config\zen") {
        "$env:USERPROFILE\.config\zen"
    } elseif (Test-Path "$env:USERPROFILE\.config\dotfiles") {
        "$env:USERPROFILE\.config\dotfiles"
    } else {
        $null
    }

    if (-not $dotfilesRoot) {
        Write-Error "Dotfiles repository directory not found."
        return
    }

    Write-Host "==> Synchronizing Zen repository ($dotfilesRoot)..." -ForegroundColor Cyan
    if (Test-Path "$dotfilesRoot\.git") {
        if (Get-Command git.exe -ErrorAction SilentlyContinue) {
            Write-Host "--> Pulling latest commits from remote..." -ForegroundColor Yellow
            try {
                $pullOutput = & git.exe -C $dotfilesRoot pull --rebase --autostash 2>&1
                $pullOutput | Write-Host
                $latestCommit = (& git.exe -C $dotfilesRoot log -1 --format='%h ("%s")' 2>$null)
                if ($latestCommit) {
                    Write-Host "✔ Repository updated: $latestCommit" -ForegroundColor Green
                }
            } catch {
                Write-Warning "git pull failed; check network or repository status."
            }
        } else {
            Write-Warning "git.exe not found on PATH; skipping git pull."
        }
    } else {
        Write-Host "Notice: '$dotfilesRoot' is not a git repository; skipping git pull." -ForegroundColor DarkGray
    }

    Write-Host "--> Synchronizing latest aliases..." -ForegroundColor Yellow

    # 1. Global Git Aliases
    if ((Get-Command git.exe -ErrorAction SilentlyContinue) -and (Test-Path "$dotfilesRoot\.gitconfig")) {
        $gitconfigPosix = "$dotfilesRoot\.gitconfig" -replace '\\', '/'
        $includes = @(& git.exe config --global --get-all include.path 2>$null)
        if ($includes -notcontains $gitconfigPosix -and $includes -notcontains "$dotfilesRoot\.gitconfig") {
            & git.exe config --global --add include.path $gitconfigPosix
        }
        Write-Host "✔ Global Git aliases synced ($dotfilesRoot\.gitconfig)" -ForegroundColor Green
    }

    # 2. Reload PowerShell Core Components
    $coreScripts = Get-ChildItem -Path "$dotfilesRoot\powershell\core\*.ps1" -ErrorAction SilentlyContinue | Sort-Object Name
    $loadedCount = 0
    foreach ($script in $coreScripts) {
        try {
            . $script.FullName
            $loadedCount++
        } catch {
            Write-Warning "Failed loading $($script.Name): $_"
        }
    }
    Write-Host "✔ Reloaded $loadedCount PowerShell core components (powershell/core/*.ps1)" -ForegroundColor Green

    # 3. Reload Local Machine Configurations if present
    $localPs1 = "$dotfilesRoot\local\local.ps1"
    if (Test-Path $localPs1) {
        . $localPs1
        Write-Host "✔ Reloaded local configurations ($localPs1)" -ForegroundColor Green
    }

    Write-Host "✔ All latest aliases and commands are now active in current session." -ForegroundColor Green
}

function _zen_alias_catalog {
    param(
        [Parameter(Position = 0)]
        [string]$Query = ""
    )

    if ($Query -in "list", "all") { $Query = "" }

    Write-Host @"

=== ZEN SHORTCUT & ALIAS DIRECTORY (Windows PowerShell) ===
Authoritative registry of navigation, system, and dev aliases
"@ -ForegroundColor Cyan

    $categories = [ordered]@{
        "ENVIRONMENT & RELOAD" = @(
            @{ Name = "rel"; Cmd = "Reload PowerShell profile (`$PROFILE)"; Desc = "Reload profile" }
            @{ Name = "gete [var]"; Cmd = "Inspect variable in Process/User/Machine"; Desc = "Inspect env vars" }
            @{ Name = "pathadd <dir>"; Cmd = "Add directory to PATH (Prepend/Append)"; Desc = "Safe PATH modification" }
            @{ Name = "set_editor [name]"; Cmd = "Set default EDITOR in User Registry & ~/.env"; Desc = "Set system editor" }
            @{ Name = "conf [key]"; Cmd = "Quick open config (env, git, ssh, profile...)"; Desc = "Config editor" }
            @{ Name = "e [file]"; Cmd = "Open target with default configured editor"; Desc = "Open in editor" }
            @{ Name = "ts"; Cmd = "[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()"; Desc = "Quick Unix timestamp" }
            @{ Name = "zen sync"; Cmd = "Pull latest commits & reload aliases"; Desc = "Sync repository" }
            @{ Name = "zen setup"; Cmd = "Modular dotfiles setup & installer"; Desc = "Dotfiles setup" }
            @{ Name = "ins / insdf"; Cmd = "zen / zen setup"; Desc = "Setup shorthand" }
        )
        "PYTHON VENV" = @(
            @{ Name = "va"; Cmd = "Activate .venv, venv, or env"; Desc = "Activate Python venv" }
            @{ Name = "vd"; Cmd = "deactivate"; Desc = "Deactivate Python venv" }
        )
        "SECURITY & NETWORK CHECK" = @(
            @{ Name = "curlip"; Cmd = "(Invoke-RestMethod https://ifconfig.me).Trim()"; Desc = "Quick public IP check" }
            @{ Name = "killport <port>"; Cmd = "Stop-Process on port with Get-NetTCPConnection"; Desc = "Terminate process by port" }
        )
        "PROCESS & SYSTEM MONITORING" = @(
            @{ Name = "wslcompact"; Cmd = "Compact ext4.vhdx using Hyper-V / DiskPart"; Desc = "Reclaim WSL disk space" }
            @{ Name = "sleepin [min]"; Cmd = "Start-Sleep & SetSuspendState (default: 30m)"; Desc = "Countdown sleep timer" }
            @{ Name = "winsleep"; Cmd = "sleepin"; Desc = "Sleep alias" }
            @{ Name = "zen sleep [min]"; Cmd = "sleepin [min]"; Desc = "Zen sleep gateway" }
        )
        "FILE & SYSTEM & NAVIGATION" = @(
            @{ Name = ".."; Cmd = "Set-Location .."; Desc = "Go up 1 directory" }
            @{ Name = "..."; Cmd = "Set-Location ../.."; Desc = "Go up 2 directories" }
            @{ Name = "ll"; Cmd = "Get-ChildItem -Path `$PWD"; Desc = "List files" }
            @{ Name = "la"; Cmd = "Get-ChildItem -Path `$PWD -Force"; Desc = "List all including hidden" }
            @{ Name = "mkcd <path>"; Cmd = "New-Item Directory & Set-Location"; Desc = "Create directory and enter" }
            @{ Name = "mktouch <path>"; Cmd = "Touch file creating parents if needed"; Desc = "Touch file" }
            @{ Name = "extract <file>"; Cmd = "Universal extractor (.zip, .tar, .gz...)"; Desc = "Extract archive" }
            @{ Name = "which <cmd>"; Cmd = "where.exe <cmd>"; Desc = "Find executable path" }
            @{ Name = "clip [text]"; Cmd = "Get-Clipboard / Set-Clipboard helper"; Desc = "Universal clipboard" }
        )
        "DIRECTORY DISK USAGE" = @(
            @{ Name = "dirsize [path]"; Cmd = "Multi-threaded robocopy disk usage breakdown"; Desc = "Folder disk sizes" }
            @{ Name = "dus [path]"; Cmd = "dirsize [path]"; Desc = "Shorthand for dirsize" }
        )
        "HISTORY SEARCH & COMMAND AUDIT" = @(
            @{ Name = "h [query] [n]"; Cmd = "Search PSReadLine persistent history"; Desc = "History search" }
            @{ Name = "clog [query]"; Cmd = "View recent confirmed commands audit log"; Desc = "Command audit log" }
            @{ Name = "cr [query|idx]"; Cmd = "Interactive picker or direct rerun from log"; Desc = "Rerun logged command" }
        )
    }

    $qLower = if ($Query) { $Query.ToLowerInvariant() } else { "" }

    foreach ($cat in $categories.Keys) {
        $items = $categories[$cat]
        $matched = @()
        foreach ($item in $items) {
            if (-not $qLower -or $item.Name.ToLowerInvariant().Contains($qLower) -or $item.Cmd.ToLowerInvariant().Contains($qLower) -or $item.Desc.ToLowerInvariant().Contains($qLower)) {
                $matched += $item
            }
        }

        if ($matched.Count -gt 0) {
            Write-Host "`n┌─[ $cat ]" -ForegroundColor DarkCyan
            foreach ($m in $matched) {
                $namePart = "  {0,-16}" -f $m.Name
                Write-Host $namePart -NoNewline -ForegroundColor Green
                Write-Host " → " -NoNewline -ForegroundColor DarkGray
                $cmdPart = "{0,-40}" -f $m.Cmd
                Write-Host $cmdPart -NoNewline -ForegroundColor White
                if ($m.Desc) {
                    Write-Host " # $($m.Desc)" -ForegroundColor DarkGray
                } else {
                    Write-Host ""
                }
            }
        }
    }

    # Also display Git Aliases if available
    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        $gitAliases = @(git.exe config --get-regexp '^alias\.' 2>$null)
        if ($gitAliases.Count -gt 0) {
            $gitMatched = @()
            foreach ($ga in $gitAliases) {
                if ($ga -match '^alias\.([^\s]+)\s+(.*)$') {
                    $aName = $Matches[1]
                    $aCmd = $Matches[2]
                    if (-not $qLower -or $aName.ToLowerInvariant().Contains($qLower) -or $aCmd.ToLowerInvariant().Contains($qLower)) {
                        $gitMatched += [PSCustomObject]@{ Name = "git $aName"; Cmd = $aCmd }
                    }
                }
            }

            if ($gitMatched.Count -gt 0) {
                Write-Host "`n┌─[ GIT CONFIGURATION SHORTCUTS ]" -ForegroundColor DarkCyan
                foreach ($gm in $gitMatched) {
                    $namePart = "  {0,-16}" -f $gm.Name
                    Write-Host $namePart -NoNewline -ForegroundColor Yellow
                    Write-Host " → " -NoNewline -ForegroundColor DarkGray
                    Write-Host "git $($gm.Cmd)" -ForegroundColor White
                }
            }
        }
    }
    Write-Host ""
}

function _zen_doctor {
    Write-Host "`n=== ZEN DOCTOR DIAGNOSTIC REPORT (Windows) ===" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Edition: $PSEdition | Version: $($PSVersionTable.PSVersion)"

    # Dotfiles root
    $dotfilesRoot = if ($global:DOTFILES_DIR -and (Test-Path $global:DOTFILES_DIR)) {
        $global:DOTFILES_DIR
    } elseif (Test-Path "$env:USERPROFILE\.config\zen") {
        "$env:USERPROFILE\.config\zen"
    } else {
        "$env:USERPROFILE\.config\dotfiles"
    }

    if (Test-Path $dotfilesRoot) {
        Write-Host "✔ Dotfiles root: $dotfilesRoot" -ForegroundColor Green
    } else {
        Write-Host "✖ Dotfiles root missing: $dotfilesRoot" -ForegroundColor Red
    }

    # Git
    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        $gitVer = (git.exe --version)
        Write-Host "✔ Git: $gitVer" -ForegroundColor Green
    } else {
        Write-Host "✖ Git not found on PATH" -ForegroundColor Yellow
    }

    # Package Manager
    $mgr = if (Get-Command winget.exe -ErrorAction SilentlyContinue) { "winget" }
           elseif (Get-Command scoop -ErrorAction SilentlyContinue) { "scoop" }
           elseif (Get-Command choco.exe -ErrorAction SilentlyContinue) { "choco" }
           else { $null }
    if ($mgr) {
        Write-Host "✔ Package Manager: $mgr" -ForegroundColor Green
    } else {
        Write-Host "✖ No supported package manager found (winget/scoop/choco)" -ForegroundColor Yellow
    }

    # Editor
    $ed = if ($env:EDITOR) { $env:EDITOR } else { "notepad.exe" }
    Write-Host "✔ Configured Editor: $ed" -ForegroundColor Green

    # Windows Terminal
    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path $wtSettings) {
        Write-Host "✔ Windows Terminal settings detected" -ForegroundColor Green
    }

    # Profile
    if ($PROFILE -and (Test-Path $PROFILE)) {
        Write-Host "✔ PowerShell profile: $PROFILE" -ForegroundColor Green
    } else {
        Write-Host "✖ Profile not found at: $PROFILE" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Universal Package Manager & Ecosystem shim
function zen {
    param(
        [Parameter(Position = 0)]
        [string]$Action = "help",
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )

    switch ($Action) {
        "sync" {
            _zen_sync -Arguments $RemainingArgs
            return
        }
        { $_ -in "ali", "alias" } {
            $q = if ($RemainingArgs.Count -gt 0) { $RemainingArgs -join " " } else { "" }
            _zen_alias_catalog -Query $q
            return
        }
        "doctor" {
            _zen_doctor
            return
        }
        "sleep" {
            if (Get-Command sleepin -ErrorAction SilentlyContinue) {
                sleepin @RemainingArgs
            } else {
                Write-Error "sleepin command not available."
            }
            return
        }
        { $_ -in "setup", "init" } {
            if (Get-Command insdf -ErrorAction SilentlyContinue) {
                insdf @RemainingArgs
            } else {
                Write-Error "Dotfiles setup command not available."
            }
            return
        }
    }

    # Package Management commands require a Windows package manager
    $mgr = if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
        "winget"
    } elseif (Get-Command scoop -ErrorAction SilentlyContinue) {
        "scoop"
    } elseif (Get-Command choco.exe -ErrorAction SilentlyContinue) {
        "choco"
    } else {
        $null
    }

    switch ($Action) {
        { $_ -in "update", "up" } {
            if (-not $mgr) { Write-Error "No supported package manager found (winget, scoop, choco)."; return }
            switch ($mgr) {
                "winget" { winget.exe source update }
                "scoop"  { scoop update }
                "choco"  { choco.exe upgrade all -y --noop }
            }
        }
        "upgrade" {
            if (-not $mgr) { Write-Error "No supported package manager found (winget, scoop, choco)."; return }
            if ($RemainingArgs.Count -eq 0) {
                Write-Warning "Notice: 'zen upgrade' requires an explicit target to prevent unintended system-wide changes."
                Write-Host @"
Usage:
  zen upgrade --all       Upgrade system packages AND managed tools
  zen upgrade system      Upgrade system package manager only
  zen upgrade <package>   Upgrade or reinstall specific package
"@
                return
            }
            switch ($mgr) {
                "winget" { winget.exe upgrade --all }
                "scoop"  { scoop update * }
                "choco"  { choco.exe upgrade all -y }
            }
        }
        { $_ -in "install", "add", "i" } {
            if (-not $mgr) { Write-Error "No supported package manager found (winget, scoop, choco)."; return }
            if ($RemainingArgs.Count -eq 0) {
                Write-Error "Error: Missing package name. Usage: zen i <package...>"
                return
            }
            switch ($mgr) {
                "winget" { winget.exe install @RemainingArgs }
                "scoop"  { scoop install @RemainingArgs }
                "choco"  { choco.exe install @RemainingArgs -y }
            }
        }
        { $_ -in "remove", "uninstall", "rm" } {
            if (-not $mgr) { Write-Error "No supported package manager found (winget, scoop, choco)."; return }
            if ($RemainingArgs.Count -eq 0) {
                Write-Error "Error: Missing package name to remove. Usage: zen rm <package...>"
                return
            }
            switch ($mgr) {
                "winget" { winget.exe uninstall @RemainingArgs }
                "scoop"  { scoop uninstall @RemainingArgs }
                "choco"  { choco.exe uninstall @RemainingArgs -y }
            }
        }
        "search" {
            if (-not $mgr) { Write-Error "No supported package manager found (winget, scoop, choco)."; return }
            if ($RemainingArgs.Count -eq 0) {
                Write-Error "Error: Missing search query. Usage: zen search <query>"
                return
            }
            switch ($mgr) {
                "winget" { winget.exe search @RemainingArgs }
                "scoop"  { scoop search @RemainingArgs }
                "choco"  { choco.exe search @RemainingArgs }
            }
        }
        default {
            $mgrDisplay = if ($mgr) { $mgr } else { "none detected (install winget or scoop)" }
            Write-Host @"
Usage: zen <command> [arguments...]

Headless Package Management:
  zen i <package...>     Install a package (shorthand for zen install)
  zen rm <package...>    Uninstall a package (shorthand for zen remove)
  zen update             Refresh package indexes
  zen upgrade --all      Upgrade all installed packages
  zen search <query>     Search for packages

Ecosystem & Workstation:
  zen sync               Pull latest commits & reload aliases into session
  zen setup [modules...] Run dotfiles installer & module setup
  zen sleep [minutes]    Put computer to sleep after countdown (default: 30)
  zen ali [query]        Search & list shortcuts and aliases
  zen doctor             Diagnose environment health & tool paths

Active manager detected: $mgrDisplay
"@
        }
    }
}
