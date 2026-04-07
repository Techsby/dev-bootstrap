#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

log() {
  printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

append_if_missing() {
  local file="$1"
  local content="$2"

  mkdir -p "$(dirname "$file")"
  touch "$file"

  if ! grep -Fq "$content" "$file"; then
    printf '%s\n' "$content" >>"$file"
  fi
}

write_file_if_missing() {
  local file="$1"
  local content="$2"

  if [[ -f "$file" ]]; then
    warn "Skipping existing file: $file"
    return 0
  fi

  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >"$file"
}

install_with_apt() {
  local packages=("$@")
  local missing=()
  local pkg

  for pkg in "${packages[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log "Installing apt packages: ${missing[*]}"
    sudo apt-get update -y
    sudo apt-get install -y "${missing[@]}"
  fi
}

is_windows_os() {
  local os_name="$1"
  case "$os_name" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

install_with_winget() {
  local package_id="$1"

  if command_exists winget; then
    winget install --id "$package_id" -e --accept-package-agreements --accept-source-agreements --silent || true
    return 0
  fi

  if command_exists powershell.exe; then
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
      "winget install --id '$package_id' -e --accept-package-agreements --accept-source-agreements --silent" || true
    return 0
  fi

  warn "winget not found. Skipping Windows package: $package_id"
}

install_windows_tools() {
  log "Installing Windows packages with winget"
  install_with_winget Git.Git
  install_with_winget Starship.Starship
  install_with_winget ajeetdsouza.zoxide
  install_with_winget OpenJS.NodeJS.LTS
  install_with_winget Wez.WezTerm
}

install_nvm_and_node() {
  if [[ ! -d "$HOME/.nvm" ]]; then
    log "Installing NVM"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi

  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  if command_exists nvm; then
    log "Installing latest LTS Node with NVM"
    nvm install --lts >/dev/null
    nvm alias default 'lts/*' >/dev/null
  else
    warn "NVM was not loaded; skipping Node installation"
  fi
}

install_node_for_windows() {
  if command_exists node; then
    return 0
  fi

  log "Installing Node LTS for Windows"
  install_with_winget OpenJS.NodeJS.LTS
}

install_pyenv() {
  if [[ -d "$HOME/.pyenv" ]]; then
    return 0
  fi

  log "Installing pyenv"
  curl -fsSL https://pyenv.run | bash
}

setup_ssh() {
  log "Configuring SSH keys"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh" 2>/dev/null || true

  if [[ ! -f "$HOME/.ssh/id_ed25519_github" ]]; then
    ssh-keygen -t ed25519 -C "github" -f "$HOME/.ssh/id_ed25519_github" -N ""
  fi

  if [[ ! -f "$HOME/.ssh/id_ed25519_gitlab" ]]; then
    ssh-keygen -t ed25519 -C "gitlab" -f "$HOME/.ssh/id_ed25519_gitlab" -N ""
  fi

  append_if_missing "$HOME/.ssh/config" "Host github.com"
  append_if_missing "$HOME/.ssh/config" "  HostName github.com"
  append_if_missing "$HOME/.ssh/config" "  User git"
  append_if_missing "$HOME/.ssh/config" "  IdentityFile ~/.ssh/id_ed25519_github"

  append_if_missing "$HOME/.ssh/config" "Host gitlab.com"
  append_if_missing "$HOME/.ssh/config" "  HostName gitlab.com"
  append_if_missing "$HOME/.ssh/config" "  User git"
  append_if_missing "$HOME/.ssh/config" "  IdentityFile ~/.ssh/id_ed25519_gitlab"

  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
}

setup_git_config() {
  log "Configuring git includes"

  git config --global includeIf.gitdir:~/dev/personal/.path "$HOME/.gitconfig-personal"
  git config --global includeIf.gitdir:~/dev/work/.path "$HOME/.gitconfig-work"

  if ! git config --global --get user.name >/dev/null; then
    git config --global user.name "Your Name"
    warn "Set your real git user.name with: git config --global user.name 'Your Name'"
  fi

  write_file_if_missing "$HOME/.gitconfig-personal" "[user]
  email = your@email.com
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519_github"

  write_file_if_missing "$HOME/.gitconfig-work" "[user]
  email = your@company.com
[core]
  sshCommand = ssh -i ~/.ssh/id_ed25519_gitlab"
}

setup_shell_config() {
  log "Configuring shell profiles"

  append_if_missing "$HOME/.zshrc" "# dev-bootstrap managed block"
  append_if_missing "$HOME/.zshrc" "export PATH=\"\$HOME/.local/bin:\$PATH\""
  append_if_missing "$HOME/.zshrc" "command -v starship >/dev/null 2>&1 && eval \"\$(starship init zsh)\""
  append_if_missing "$HOME/.zshrc" "command -v zoxide >/dev/null 2>&1 && eval \"\$(zoxide init zsh)\""

  append_if_missing "$HOME/.bashrc" "# dev-bootstrap managed block"
  append_if_missing "$HOME/.bashrc" "export PATH=\"\$HOME/.local/bin:\$PATH\""
  append_if_missing "$HOME/.bashrc" "command -v starship >/dev/null 2>&1 && eval \"\$(starship init bash)\""
  append_if_missing "$HOME/.bashrc" "command -v zoxide >/dev/null 2>&1 && eval \"\$(zoxide init bash)\""

  write_file_if_missing "$HOME/.config/starship.toml" "add_newline = false
format = \"\$directory\$git_branch\$git_status\$nodejs\$python\$character\"

[character]
success_symbol = \"[>](green)\"
error_symbol = \"[>](red)\""

  write_file_if_missing "$HOME/.config/ghostty/config" "font-family = JetBrainsMono Nerd Font
font-size = 13
theme = dark"

  write_file_if_missing "$HOME/.wezterm.lua" "local wezterm = require 'wezterm'

return {
  font = wezterm.font('JetBrainsMono Nerd Font'),
  font_size = 13,
  enable_tab_bar = false,
}"
}

main() {
  log "Starting development environment bootstrap"

  if ! command_exists curl; then
    die "curl is required but not installed"
  fi

  local os
  os="$(uname -s)"
  log "Detected OS: $os"

  if [[ "$os" == "Linux" ]]; then
    install_with_apt git zsh fzf curl ca-certificates build-essential unzip xz-utils

    if ! command_exists starship; then
      log "Installing starship"
      curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    fi

    if ! command_exists zoxide; then
      log "Installing zoxide"
      curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    fi

    if ! command_exists eza; then
      install_with_apt eza || warn "Package 'eza' unavailable on this distro"
    fi

    if ! command_exists bat; then
      install_with_apt bat || warn "Package 'bat' unavailable on this distro"
    fi
  elif [[ "$os" == "Darwin" ]]; then
    if ! command_exists brew; then
      log "Installing Homebrew"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    log "Installing Homebrew packages"
    brew install git zsh starship fzf zoxide eza bat curl
  elif is_windows_os "$os"; then
    install_windows_tools
    install_node_for_windows
  else
    die "Unsupported OS: $os. Supported: Linux, macOS, Windows (Git Bash/MSYS/Cygwin)."
  fi

  if is_windows_os "$os"; then
    warn "Skipping NVM install on native Windows; Node LTS is installed via winget."
    warn "Skipping pyenv install on native Windows. Use pyenv-win if needed."
  else
    install_nvm_and_node
    install_pyenv
  fi

  mkdir -p "$HOME/dev/personal" "$HOME/dev/work"

  setup_ssh
  setup_git_config
  setup_shell_config

  if ! is_windows_os "$os" && command_exists zsh; then
    chsh -s "$(command -v zsh)" || warn "Could not change default shell automatically"
  fi

  log "Bootstrap complete"
  printf '\nNext steps:\n'
  printf '1) Restart your terminal\n'
  printf '2) Add SSH public keys to GitHub and GitLab\n'
  printf '3) Update git emails in ~/.gitconfig-personal and ~/.gitconfig-work\n\n'
}

main "$@"
