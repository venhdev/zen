# Cross-platform environment detection and standard OS primitives (Linux, macOS, Windows)

# Detect Operating System Family
_detect_os() {
  case "$OSTYPE" in
    darwin*)
      echo "darwin"
      return
      ;;
    msys*|cygwin*)
      echo "msys"
      return
      ;;
    linux*)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/version && "$(< /proc/version)" == *[Mm]icrosoft* ]]; then
        echo "wsl"
      elif [[ "$(uname -r 2>/dev/null)" == *[Mm]icrosoft* ]]; then
        echo "wsl"
      else
        echo "linux"
      fi
      return
      ;;
  esac

  local uname_out
  uname_out="$(uname -s 2>/dev/null || echo "Unknown")"

  case "$uname_out" in
    Darwin*)
      echo "darwin"
      ;;
    MSYS*|MINGW*|CYGWIN*)
      echo "msys"
      ;;
    Linux*)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -f /proc/version && "$(< /proc/version)" == *[Mm]icrosoft* ]] || [[ "$(uname -r 2>/dev/null)" == *[Mm]icrosoft* ]]; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Detect Linux Distribution Family (from /etc/os-release without external subshell forks)
_detect_distro() {
  if [[ -f /etc/os-release ]]; then
    typeset -l id="" id_like=""
    local k v
    while IFS='=' read -r k v || [[ -n "$k" ]]; do
      v="${v%\"}"
      v="${v#\"}"
      v="${v%\'}"
      v="${v#\'}"
      case "$k" in
        ID) id="$v" ;;
        ID_LIKE) id_like="$v" ;;
      esac
      [[ -n "$id" && -n "$id_like" ]] && break
    done < /etc/os-release
    echo "${id:-${id_like:-linux}}"
  else
    echo "unknown"
  fi
}

# Detect Windows Host System Directory
_detect_win_dir() {
  if [[ -n "${DOTFILES_WIN_PATH:-}" && -d "$DOTFILES_WIN_PATH" ]]; then
    echo "$DOTFILES_WIN_PATH"
  elif [[ -d "/c/Windows" ]]; then
    echo "/c/Windows"
  elif [[ -d "/mnt/c/Windows" ]]; then
    echo "/mnt/c/Windows"
  else
    echo "/mnt/c/Windows"
  fi
}

_OS_TYPE="$(_detect_os)"
_LINUX_DISTRO="$(_detect_distro)"
_WIN_DIR="$(_detect_win_dir)"

# SSOT Boolean Helper Functions
is_darwin() { [[ "$_OS_TYPE" == "darwin" ]]; }
is_mac() { is_darwin; }
is_wsl() { [[ "$_OS_TYPE" == "wsl" ]]; }
is_msys() { [[ "$_OS_TYPE" == "msys" ]]; }
is_linux() { [[ "$_OS_TYPE" == "linux" || "$_OS_TYPE" == "wsl" ]]; }
is_pure_linux() { [[ "$_OS_TYPE" == "linux" ]]; }
is_windows() { [[ "$_OS_TYPE" == "msys" || "$_OS_TYPE" == "wsl" ]]; }
has_apt() { command -v apt-get >/dev/null 2>&1; }

# Cross-platform clipboard helper
clip() {
  case "$_OS_TYPE" in
    darwin)
      if command -v pbcopy &>/dev/null; then
        pbcopy "$@"
        return $?
      fi
      ;;
    wsl|msys)
      local clip_exe="${DOTFILES_WIN_PATH:-$_WIN_DIR}/System32/clip.exe"
      if [[ -x "$clip_exe" ]]; then
        "$clip_exe" "$@"
        return $?
      elif command -v clip.exe &>/dev/null; then
        clip.exe "$@"
        return $?
      fi
      ;;
    linux)
      if [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy &>/dev/null; then
        wl-copy "$@"
        return $?
      elif command -v xclip &>/dev/null; then
        xclip -selection clipboard "$@"
        return $?
      elif command -v xsel &>/dev/null; then
        xsel --clipboard --input "$@"
        return $?
      fi
      ;;
  esac

  echo "❌ No supported clipboard utility found (pbcopy, clip.exe, wl-copy, xclip, xsel)" >&2
  return 1
}

# Cross-platform file / URL opener
open_target() {
  local target="${1:-.}"

  case "$_OS_TYPE" in
    darwin)
      open "$target"
      ;;
    wsl)
      if command -v wslpath &>/dev/null && [[ -e "$target" ]]; then
        explorer.exe "$(wslpath -w "$target")"
      else
        explorer.exe "$target"
      fi
      ;;
    msys)
      explorer.exe "$target"
      ;;
    linux)
      if command -v xdg-open &>/dev/null; then
        xdg-open "$target" &>/dev/null &
      else
        echo "❌ xdg-open not found" >&2
        return 1
      fi
      ;;
    *)
      echo "❌ No supported opener found for OS: $_OS_TYPE" >&2
      return 1
      ;;
  esac
}

# Self-locating Dotfiles Root Resolver
_get_dotfiles_root() {
  if [[ -n "${ZEN_DIR:-}" && -d "$ZEN_DIR" ]]; then
    echo "$ZEN_DIR"
    return
  fi
  if [[ -n "${ZEN:-}" && -d "$ZEN" ]]; then
    echo "$ZEN"
    return
  fi
  if [[ -n "${DOTFILES:-}" && -d "$DOTFILES" ]]; then
    echo "$DOTFILES"
    return
  fi
  if [[ -n "${DOTFILES_DIR:-}" && -d "$DOTFILES_DIR" ]]; then
    echo "$DOTFILES_DIR"
    return
  fi
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
  if [[ -n "$self_dir" && -d "$self_dir/.." && -f "$self_dir/../install.sh" ]]; then
    (cd "$self_dir/.." && pwd)
    return
  fi
  local xdg_zen="${XDG_CONFIG_HOME:-$HOME/.config}/zen"
  if [[ -d "$xdg_zen" ]]; then
    echo "$xdg_zen"
    return
  fi
  local xdg_dotfiles="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
  if [[ -d "$xdg_dotfiles" ]]; then
    echo "$xdg_dotfiles"
    return
  fi
  echo "$HOME/.config/zen"
}

# zen: Unified Ecosystem Gateway, Package Manager & Tools Orchestrator
zen() {
  local subcmd="${1:-}"
  local dotfiles_root="$(_get_dotfiles_root)"

  case "$subcmd" in
    ""|tui)
      local installer="$dotfiles_root/scripts/install-tools.sh"
      if [[ -f "$installer" ]]; then
        bash "$installer"
      else
        echo "Error: Developer tools notebook installer not found at $installer" >&2
        return 1
      fi
      ;;

    i|install)
      shift
      _zen_cmd_install "$@"
      ;;

    rm|remove|uninstall)
      shift
      _zen_cmd_remove "$@"
      ;;

    update|up)
      shift
      _zen_cmd_update "$@"
      ;;

    upgrade)
      shift
      _zen_cmd_upgrade "$@"
      ;;

    search)
      shift
      _zen_cmd_search "$@"
      ;;

    setup|init)
      shift
      local installer="$dotfiles_root/install.sh"
      if [[ -f "$installer" ]]; then
        bash "$installer" "$@"
      else
        echo "Error: Dotfiles installer not found at $installer" >&2
        return 1
      fi
      ;;

    sync)
      shift
      _zen_cmd_sync "$@"
      ;;

    doctor)
      shift
      local doctor_lib="$dotfiles_root/core/45-doctor-lib.sh"
      if [[ -f "$doctor_lib" ]]; then
        # shellcheck source=./45-doctor-lib.sh
        . "$doctor_lib"
        _zen_doctor "$@"
      else
        echo "Error: Doctor module not found at $doctor_lib" >&2
        return 1
      fi
      ;;

    ali|alias)
      shift
      local alias_lib="$dotfiles_root/core/12-alias-catalog-lib.sh"
      if [[ -f "$alias_lib" ]]; then
        # shellcheck source=./12-alias-catalog-lib.sh
        . "$alias_lib"
        _zen_alias_catalog "$@"
      else
        echo "Error: Alias catalog module not found at $alias_lib" >&2
        return 1
      fi
      ;;

    sleep)
      shift
      if declare -F sleepin >/dev/null 2>&1; then
        sleepin "$@"
      else
        local minutes="${1:-30}"
        if ! [[ "$minutes" =~ ^[0-9]+$ ]] || (( minutes < 0 )); then
          echo "Usage: zen sleep [minutes] (default: 30)" >&2
          return 1
        fi
        echo "Computer will sleep in $minutes minute(s). Press Ctrl+C to cancel."
        local psh="${DOTFILES_WIN_PATH:-$_WIN_DIR}/System32/WindowsPowerShell/v1.0/powershell.exe"
        if [[ -x "$psh" ]]; then
          "$psh" -NoProfile -Command "Start-Sleep -Seconds ($minutes * 60); Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport(\"PowrProf.dll\", SetLastError = true)] public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);'; [Win32.Power]::SetSuspendState(\$false, \$false, \$false) | Out-Null"
        elif command -v powershell.exe >/dev/null 2>&1; then
          powershell.exe -NoProfile -Command "Start-Sleep -Seconds ($minutes * 60); Add-Type -Namespace Win32 -Name Power -MemberDefinition '[DllImport(\"PowrProf.dll\", SetLastError = true)] public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);'; [Win32.Power]::SetSuspendState(\$false, \$false, \$false) | Out-Null"
        else
          echo "Error: Windows PowerShell not found to initiate system sleep." >&2
          return 1
        fi
      fi
      ;;

    ski)
      shift
      _zen_cmd_ski "$@"
      ;;

    skiv)
      shift
      _zen_cmd_ski "venhdev/skills" "$@"
      ;;

    skiva)
      shift
      _zen_cmd_ski "venhdev/skills" --all "$@"
      ;;

    --all|-a)
      local installer="$dotfiles_root/scripts/install-tools.sh"
      if [[ -f "$installer" ]]; then
        bash "$installer" --all
      else
        echo "Error: Developer tools notebook installer not found at $installer" >&2
        return 1
      fi
      ;;

    -h|--help|help)
      _zen_help
      ;;

    *)
      echo "❌ Unknown subcommand: '$subcmd'" >&2
      echo "Run 'zen --help' for available commands and usage." >&2
      return 1
      ;;
  esac
}

_zen_cmd_install() {
  if [[ $# -eq 0 ]]; then
    echo "❌ Error: Missing package name or option." >&2
    echo
    echo "Usage:" >&2
    echo "  zen i <pkg...>       Install system package(s) or managed tool(s)" >&2
    echo "  zen i --all          Batch install all missing managed tools" >&2
    return 1
  fi

  if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    local installer="$(_get_dotfiles_root)/scripts/install-tools.sh"
    bash "$installer" --all
    return $?
  fi

  _zen_package_action "install" "$@"
}

_zen_cmd_remove() {
  if [[ $# -eq 0 ]]; then
    echo "❌ Error: Missing package name to remove." >&2
    echo
    echo "Usage:" >&2
    echo "  zen rm <pkg...>      Uninstall package(s)" >&2
    return 1
  fi
  _zen_package_action "remove" "$@"
}

_zen_cmd_update() {
  local check_all=0
  if [[ "${1:-}" == "--all" || "${1:-}" == "-a" ]]; then
    check_all=1
  fi

  echo "==> Updating package repository indexes..."
  _zen_package_action "update"

  if (( check_all )); then
    echo
    echo "==> Tracking managed developer tools..."
    local manifest_file="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/.installed.json"
    if [[ -f "$manifest_file" ]] && command -v python3 >/dev/null 2>&1; then
      python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    tools = data.get("tools", {})
    if tools:
        print(f"Tracking {len(tools)} managed tools in .installed.json:")
        for k, v in sorted(tools.items()):
            print(f"  • {k:10s} (v{v.get(\"installed_version\", \"?\")}) origin: {v.get(\"origin\", \"?\")}")
except Exception:
    pass
' "$manifest_file" 2>/dev/null || true
    fi
  fi
}

_zen_cmd_upgrade() {
  if [[ $# -eq 0 ]]; then
    echo "⚠️  Notice: 'zen upgrade' requires an explicit target to prevent unintended system-wide modifications." >&2
    echo
    echo "Usage:" >&2
    echo "  zen upgrade --all       Upgrade system packages AND managed developer tools" >&2
    echo "  zen upgrade system      Upgrade system packages only (apt/brew/pacman/winget)" >&2
    echo "  zen upgrade <pkg...>    Upgrade/reinstall specific package(s)" >&2
    return 1
  fi

  case "$1" in
    --all|-a)
      echo "==> Upgrading system packages..."
      _zen_package_action "upgrade"
      echo
      echo "==> Updating managed developer tools..."
      local installer="$(_get_dotfiles_root)/scripts/install-tools.sh"
      bash "$installer" --all
      ;;
    system)
      echo "==> Upgrading system packages..."
      _zen_package_action "upgrade"
      ;;
    *)
      _zen_package_action "install" "$@"
      ;;
  esac
}

_zen_cmd_search() {
  if [[ $# -eq 0 ]]; then
    echo "❌ Error: Missing search query." >&2
    echo "Usage: zen search <query>" >&2
    return 1
  fi
  _zen_package_action "search" "$@"
}

_zen_ski_help() {
  cat <<'EOF'
zen ski - Agent Skills Orchestrator (powered by Vercel Skills CLI)

Usage:
  zen ski <source> [options]         Add skill(s) from GitHub, URL, or local path
  zen skiv [options]                 Add personal skills (venhdev/skills)
  zen skiva                          Batch install all personal skills non-interactively (--all)

Common Management:
  zen ski rm <skill...>              Remove installed agent skill(s)
  zen ski ls [-g]                    List installed skills (project or global -g)
  zen ski update                     Update installed skills to latest versions
  zen ski find [query]               Search agent skills interactively
  zen ski check                      Check for available skill updates

Add Options:
  -g, --global                       Install to user directory (~/<agent>/skills)
  -a, --agent <agents...>            Target specific agent(s) (e.g. claude-code, codex, cursor, *)
  -s, --skill <skills...>            Specify skill names to install (use '*' for all)
  -l, --list                         List available skills in source without installing
  -y, --yes                          Skip confirmation prompts
  --all                              Shorthand for --skill '*' --agent '*' -y
  --copy                             Copy files instead of symlinking

Examples:
  zen ski vercel-labs/agent-skills
  zen skiv -l
  zen skiv -s clarify
  zen skiva
EOF
}

_zen_cmd_ski() {
  if ! command -v npx >/dev/null 2>&1; then
    echo "❌ Error: 'npx' is required to manage agent skills." >&2
    echo "💡 Run 'zen i node' (or install Node.js) to enable skills management." >&2
    return 1
  fi

  if [[ $# -eq 0 ]]; then
    _zen_ski_help
    return 0
  fi

  local action="${1:-}"
  case "$action" in
    -h|--help|help)
      _zen_ski_help
      ;;
    rm|remove)
      shift
      npx --yes skills remove "$@"
      ;;
    ls|list)
      shift
      npx --yes skills list "$@"
      ;;
    update|up|upgrade)
      shift
      npx --yes skills update "$@"
      ;;
    find)
      shift
      npx --yes skills find "$@"
      ;;
    check)
      shift
      npx --yes skills check "$@"
      ;;
    init)
      shift
      npx --yes skills init "$@"
      ;;
    add)
      shift
      npx --yes skills add "$@"
      ;;
    v|venh)
      shift
      npx --yes skills add venhdev/skills "$@"
      ;;
    va|venha)
      shift
      npx --yes skills add venhdev/skills --all "$@"
      ;;
    *)
      npx --yes skills add "$@"
      ;;
  esac
}

_zen_cmd_sync() {
  local dotfiles_root="$(_get_dotfiles_root)"

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: zen sync [OPTIONS]"
    echo
    echo "Pull latest commits from remote and reload aliases without running setup."
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo
    echo "Note: To reconfigure system modules or run full provisioning, use 'zen setup'."
    return 0
  fi

  echo "==> Synchronizing Zen repository ($dotfiles_root)..."
  if [[ -d "$dotfiles_root/.git" ]]; then
    echo "--> Pulling latest commits from remote..."
    if git -C "$dotfiles_root" pull --rebase --autostash; then
      local latest_commit
      latest_commit="$(git -C "$dotfiles_root" log -1 --format='%h ("%s")' 2>/dev/null || true)"
      [[ -n "$latest_commit" ]] && echo "✔ Repository updated: $latest_commit"
    else
      echo "⚠️  Warning: git pull failed; check network or repository status." >&2
    fi
  else
    echo "Notice: '$dotfiles_root' is not a git repository; skipping git pull."
  fi

  echo "--> Synchronizing latest aliases..."

  # 1. Ensure global git aliases are included
  if command -v git >/dev/null 2>&1 && [[ -f "$dotfiles_root/.gitconfig" ]]; then
    if ! git config --global --get-all include.path 2>/dev/null | grep -Fxq "$dotfiles_root/.gitconfig"; then
      git config --global --add include.path "$dotfiles_root/.gitconfig"
    fi
    echo "✔ Global Git aliases synced ($dotfiles_root/.gitconfig)"
  fi

  # 2. Source local env if present
  if [[ -r "$dotfiles_root/local/local.env" ]]; then
    # shellcheck source=/dev/null
    . "$dotfiles_root/local/local.env"
  fi

  # 3. Reload shell core aliases
  shopt -s expand_aliases 2>/dev/null || true
  local alias_count=0
  if [[ -f "$dotfiles_root/core/10-base-aliases.sh" ]]; then
    # shellcheck source=/dev/null
    . "$dotfiles_root/core/10-base-aliases.sh"
    alias_count=$(grep -cE '^[[:space:]]*alias ' "$dotfiles_root/core/10-base-aliases.sh" 2>/dev/null || echo 0)
    echo "✔ Reloaded $alias_count shell aliases (core/10-base-aliases.sh)"
  fi

  # 4. Reload enabled modules
  local mod_count=0
  if [[ -d "$dotfiles_root/enabled.d" ]]; then
    for _mod in "$dotfiles_root"/enabled.d/*.sh; do
      if [[ -r "$_mod" ]]; then
        # shellcheck source=/dev/null
        . "$_mod"
        ((mod_count++))
      fi
    done
  fi
  if (( mod_count > 0 )); then
    echo "✔ Reloaded $mod_count active modules (enabled.d)"
  fi

  # 5. Reload platform library and alias catalog
  if [[ -f "$dotfiles_root/core/00-platform-lib.sh" ]]; then
    # shellcheck source=/dev/null
    . "$dotfiles_root/core/00-platform-lib.sh"
  fi
  if [[ -f "$dotfiles_root/core/12-alias-catalog-lib.sh" ]]; then
    # shellcheck source=/dev/null
    . "$dotfiles_root/core/12-alias-catalog-lib.sh"
  fi

  echo "✔ All latest aliases are now active in current session."
}

_zen_package_action() {
  local action="$1"
  shift

  local mgr=""
  if command -v brew &>/dev/null; then
    mgr="brew"
  elif command -v apt-get &>/dev/null; then
    mgr="apt"
  elif command -v pacman &>/dev/null; then
    mgr="pacman"
  elif command -v dnf &>/dev/null; then
    mgr="dnf"
  elif command -v winget.exe &>/dev/null; then
    mgr="winget"
  elif command -v scoop &>/dev/null; then
    mgr="scoop"
  fi

  if [[ -z "$mgr" ]]; then
    echo "❌ No supported package manager found (brew, apt, pacman, dnf, winget, scoop)" >&2
    return 1
  fi

  case "$action" in
    update)
      case "$mgr" in
        brew)   brew update ;;
        apt)    sudo apt update ;;
        pacman) sudo pacman -Sy ;;
        dnf)    sudo dnf check-update ;;
        winget) winget.exe source update ;;
        scoop)  scoop update ;;
      esac
      ;;
    upgrade)
      case "$mgr" in
        brew)   brew upgrade ;;
        apt)    sudo apt update && sudo apt upgrade -y ;;
        pacman) sudo pacman -Syu ;;
        dnf)    sudo dnf upgrade -y ;;
        winget) winget.exe upgrade --all ;;
        scoop)  scoop update * ;;
      esac
      ;;
    install|add)
      case "$mgr" in
        brew)   brew install "$@" ;;
        apt)    sudo apt install "$@" ;;
        pacman) sudo pacman -S "$@" ;;
        dnf)    sudo dnf install "$@" ;;
        winget) winget.exe install "$@" ;;
        scoop)  scoop install "$@" ;;
      esac
      ;;
    remove|uninstall)
      case "$mgr" in
        brew)   brew uninstall "$@" ;;
        apt)    sudo apt remove "$@" ;;
        pacman) sudo pacman -R "$@" ;;
        dnf)    sudo dnf remove "$@" ;;
        winget) winget.exe uninstall "$@" ;;
        scoop)  scoop uninstall "$@" ;;
      esac
      ;;
    search)
      case "$mgr" in
        brew)   brew search "$@" ;;
        apt)    apt search "$@" ;;
        pacman) pacman -Ss "$@" ;;
        dnf)    dnf search "$@" ;;
        winget) winget.exe search "$@" ;;
        scoop)  scoop search "$@" ;;
      esac
      ;;
  esac
}

_zen_help() {
  local mgr=""
  if command -v brew &>/dev/null; then
    mgr="brew"
  elif command -v apt-get &>/dev/null; then
    mgr="apt"
  elif command -v pacman &>/dev/null; then
    mgr="pacman"
  elif command -v dnf &>/dev/null; then
    mgr="dnf"
  elif command -v winget.exe &>/dev/null; then
    mgr="winget"
  elif command -v scoop &>/dev/null; then
    mgr="scoop"
  fi

  cat <<EOF
zen - Unified Ecosystem Gateway & Developer Tool Orchestrator

Usage:
  zen [subcommand] [arguments...]

TUI & Tools Notebook:
  zen                      Launch interactive Developer Tools Notebook TUI (zen tui)
  zen tui                  Launch interactive Developer Tools Notebook TUI

Headless Package Management:
  zen i <pkg...>           Install system package(s) or managed tool(s)
  zen i --all              Batch install missing managed dev tools
  zen rm <pkg...>          Uninstall package(s)
  zen update [--all]       Refresh package index indexes (--all includes tool metadata)
  zen upgrade --all        Upgrade system packages AND managed developer tools
  zen upgrade system       Upgrade system package manager only
  zen upgrade <pkg...>     Upgrade or reinstall specific package(s)
  zen search <query>       Search for packages in repository

Agent Skills Management:
  zen ski [source|cmd]     Agent skills orchestrator (add, rm, ls, update, find)
  zen skiv [options]       Add personal skills from venhdev/skills
  zen skiva                Batch install all personal skills non-interactively (--all)

Ecosystem & Workstation:
  zen doctor               Audit ecosystem health (OS, symlinks, git, hooks, tools)
  zen ali [list|query]     Directory & search for all dotfiles shortcuts and aliases
  zen setup [modules...]   Run dotfiles modular configuration and setup (replaces insdf)
  zen sync                 Pull latest git commits and reload newest aliases
  zen sleep [minutes]      Put Windows machine to sleep after countdown (default: 30)

Active system manager: ${mgr:-none}
EOF
}

# Shell-aware reload helper (supports both Bash and Zsh)
unalias rel 2>/dev/null || true
rel() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    local zsh_rc="${ZDOTDIR:-$HOME}/.zshrc"
    if [[ -r "$zsh_rc" ]]; then
      # shellcheck disable=SC1090
      source "$zsh_rc"
      echo "✓ Reloaded $zsh_rc"
      return 0
    fi
  fi

  local bash_rc="$HOME/.bashrc"
  if [[ -r "$bash_rc" ]]; then
    # shellcheck disable=SC1090
    source "$bash_rc"
    echo "✓ Reloaded $bash_rc"
    return 0
  fi

  echo "❌ Neither ~/.zshrc nor ~/.bashrc found to reload." >&2
  return 1
}
