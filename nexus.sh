#!/bin/bash

# ==============================================================================
# Nexus Node Deployment & Management Script
# 
# Features:
# - Auto-install dependencies (Homebrew, Rust, CMake, Protobuf)
# - Auto-install/Update Nexus CLI
# - Automated Node ID configuration
# - Automatic updates monitoring (every 30 mins)
# - Graceful shutdown and restart handling
# - Support for macOS (Terminal) and Linux (Screen)
# ==============================================================================

# --- Configuration ---
GREEN='\033[1;32m'
BLUE='\033[1;36m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

NEXUS_HOME="$HOME/.nexus"
LOG_FILE="$HOME/nexus.log"
CONFIG_FILE="$NEXUS_HOME/config.json"
MAX_LOG_SIZE=$((10 * 1024 * 1024)) # 10MB
REPO_URL="https://github.com/nexus-xyz/nexus-cli.git"
SCRIPT_URL="https://raw.githubusercontent.com/Xiaofei-Z/nex/main/nexus.sh"

# Ensure Nexus config directory exists
mkdir -p "$NEXUS_HOME"

# --- System Detection ---
OS=$(uname -s)
case "$OS" in
  Darwin) OS_TYPE="macOS" ;;
  Linux)
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      if [[ "$ID" == "ubuntu" ]]; then
        OS_TYPE="Ubuntu"
      else
        OS_TYPE="Linux"
      fi
    else
      OS_TYPE="Linux"
    fi
    ;;
  *) echo -e "${RED}Unsupported OS: $OS. Only macOS and Ubuntu/Linux are supported.${NC}" ; exit 1 ;;
esac

# Detect Shell Configuration
if [[ -n "$ZSH_VERSION" ]]; then
  SHELL_CONFIG="$HOME/.zshrc"
elif [[ -n "$BASH_VERSION" ]]; then
  SHELL_CONFIG="$HOME/.bashrc"
else
  SHELL_CONFIG="$HOME/.profile"
fi

# --- Helper Functions ---

log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S %Z')
  echo -e "[$timestamp] $1" | tee -a "$LOG_FILE"
  rotate_log
}

rotate_log() {
  if [[ -f "$LOG_FILE" ]]; then
    local file_size
    if [[ "$OS_TYPE" == "macOS" ]]; then
      file_size=$(stat -f %z "$LOG_FILE" 2>/dev/null || echo 0)
    else
      file_size=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)
    fi
    
    if (( file_size >= MAX_LOG_SIZE )); then
      mv "$LOG_FILE" "${LOG_FILE}.$(date +%F_%H-%M-%S).bak"
      echo -e "${YELLOW}Log rotated. New log: $LOG_FILE${NC}"
    fi
  fi
}

print_header() {
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

check_command() {
  command -v "$1" &> /dev/null
}

add_path_to_shell() {
  local new_path="$1"
  local entry="export PATH=\"$new_path:\$PATH\""
  
  if [[ -f "$SHELL_CONFIG" ]] && grep -Fq "$new_path" "$SHELL_CONFIG"; then
    log "${GREEN}PATH $new_path already in $SHELL_CONFIG${NC}"
  else
    log "${BLUE}Adding $new_path to $SHELL_CONFIG...${NC}"
    echo "$entry" >> "$SHELL_CONFIG"
    export PATH="$new_path:$PATH"
  fi
}

# --- Cleanup Functions ---

kill_process_by_pid() {
  local pid=$1
  if ps -p "$pid" > /dev/null 2>&1; then
    kill -TERM "$pid" 2>/dev/null
    sleep 1
    if ps -p "$pid" > /dev/null 2>&1; then
      kill -KILL "$pid" 2>/dev/null
    fi
  fi
}

cleanup_process() {
  local mode=$1 # 'exit' or 'restart'
  log "${YELLOW}Initiating cleanup ($mode)...${NC}"

  if [[ "$OS_TYPE" == "macOS" ]]; then
    # Close specific Terminal window
    local win_id=$(osascript -e 'tell app "Terminal" to id of first window whose name contains "node-id"' 2>/dev/null)
    if [[ -n "$win_id" ]]; then
      log "${BLUE}Closing Nexus Terminal window (ID: $win_id)...${NC}"
      osascript -e "tell application \"Terminal\" to close window id $win_id saving no" 2>/dev/null
    fi
  fi

  # Kill processes
  local pids=$(pgrep -f "nexus-cli|nexus-network" | tr '\n' ' ')
  if [[ -n "$pids" ]]; then
    log "${BLUE}Terminating Nexus processes: $pids${NC}"
    for pid in $pids; do kill_process_by_pid "$pid"; done
  fi

  # Clean screen session on Linux
  if screen -list | grep -q "nexus_node"; then
    screen -S nexus_node -X quit 2>/dev/null
  fi

  # Clean child processes
  local child_pids=$(pgrep -P $(pgrep -f "nexus-cli|nexus-network" | tr '\n' ' ') 2>/dev/null)
  if [[ -n "$child_pids" ]]; then
    for pid in $child_pids; do kill -9 "$pid" 2>/dev/null; done
  fi

  if [[ "$mode" == "exit" ]]; then
    log "${GREEN}Cleanup finished. Exiting.${NC}"
    exit 0
  else
    log "${GREEN}Cleanup finished. Ready for restart.${NC}"
    if [[ -f "$LOG_FILE" ]]; then rm -f "$LOG_FILE"; fi
  fi
}

trap 'cleanup_process exit' SIGINT SIGTERM SIGHUP

# --- Installation Functions ---

install_system_dependencies() {
  print_header "Checking System Dependencies"
  
  if [[ "$OS_TYPE" == "Ubuntu" ]]; then
    sudo apt-get update -y
    sudo apt-get install -y curl jq screen build-essential cmake protobuf-compiler git unzip || {
      log "${RED}Failed to install dependencies (apt).${NC}"
      exit 1
    }
  elif [[ "$OS_TYPE" == "macOS" ]]; then
    if ! check_command brew; then
      log "${BLUE}Installing Homebrew...${NC}"
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      add_path_to_shell "/opt/homebrew/bin"
    fi
    
    # Check individual brew packages
    for pkg in cmake protobuf; do
      if ! check_command $pkg; then
        log "${BLUE}Installing $pkg via Homebrew...${NC}"
        brew install $pkg
      fi
    done
  fi
}

install_rust() {
  print_header "Checking Rust Installation"
  if check_command rustc; then
    log "${GREEN}Rust is already installed.$(rustc --version)${NC}"
  else
    log "${BLUE}Installing Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    add_path_to_shell "$HOME/.cargo/bin"
  fi

  # Add RISC-V target
  if ! rustup target list --installed | grep -q "riscv32i-unknown-none-elf"; then
    log "${BLUE}Adding RISC-V target...${NC}"
    rustup target add riscv32i-unknown-none-elf
  else
    log "${GREEN}RISC-V target already installed.${NC}"
  fi
}

install_nexus_cli() {
  local attempt=1
  local max_attempts=3
  
  while [[ $attempt -le $max_attempts ]]; do
    log "${BLUE}Installing/Updating Nexus CLI (Attempt $attempt/$max_attempts)...${NC}"
    if curl -s https://cli.nexus.xyz/ | sh &>/dev/null; then
      log "${GREEN}Nexus CLI installed successfully.${NC}"
      
      # Refresh environment
      source "$SHELL_CONFIG" 2>/dev/null
      if [[ -f "$HOME/.cargo/env" ]]; then source "$HOME/.cargo/env"; fi
      
      # Verify installation
      if check_command nexus-cli; then
        log "${GREEN}Version: $(nexus-cli -V)${NC}"
        return 0
      elif check_command nexus-network; then
        log "${GREEN}Version: $(nexus-network --version)${NC}"
        return 0
      fi
    fi
    ((attempt++))
    sleep 3
  done
  
  log "${RED}Failed to install Nexus CLI after $max_attempts attempts.${NC}"
  # Don't exit here, might try to run existing version
}

# --- Node Configuration ---

configure_node_id() {
  # Check env var first (for non-interactive mode)
  if [[ -n "$NEXUS_NODE_ID" ]]; then
    echo "{\"node_id\": \"$NEXUS_NODE_ID\"}" > "$CONFIG_FILE"
    NODE_ID_TO_USE="$NEXUS_NODE_ID"
    log "${GREEN}Using Node ID from environment: $NODE_ID_TO_USE${NC}"
    return
  fi

  local current_id=""
  if [[ -f "$CONFIG_FILE" ]]; then
    current_id=$(jq -r .node_id "$CONFIG_FILE" 2>/dev/null)
  fi

  if [[ -n "$current_id" && "$current_id" != "null" ]]; then
    log "${GREEN}Found existing Node ID: $current_id${NC}"
    echo -e "${BLUE}Use this ID? (y/n) [Default: y, Timeout: 5s]${NC}"
    read -t 5 -r choice || choice="y"
    
    if [[ "$choice" =~ ^[Nn]$ ]]; then
      read -rp "Enter new Node ID: " NODE_ID_TO_USE
    else
      NODE_ID_TO_USE="$current_id"
    fi
  else
    log "${YELLOW}No Node ID found.${NC}"
    read -rp "Enter new Node ID: " NODE_ID_TO_USE
  fi

  # Validate
  if [[ ! "$NODE_ID_TO_USE" =~ ^[a-zA-Z0-9-]+$ ]]; then
    log "${RED}Invalid Node ID. Alphanumeric and hyphens only.${NC}"
    exit 1
  fi

  # Save
  echo "{\"node_id\": \"$NODE_ID_TO_USE\"}" > "$CONFIG_FILE"
  log "${GREEN}Node ID configured: $NODE_ID_TO_USE${NC}"
}

# --- Update Check ---

check_updates() {
  log "${BLUE}Checking for updates...${NC}"
  local latest_tag=$(git ls-remote --tags "$REPO_URL" | grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/.*refs\/tags\///' | sort -V | tail -1)
  
  if [[ -z "$latest_tag" ]]; then
    log "${YELLOW}Could not fetch latest version info.${NC}"
    return 1
  fi

  # Get current version
  local current_version=""
  if check_command nexus-cli; then
    current_version=$(nexus-cli -V | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  elif check_command nexus-network; then
    current_version=$(nexus-network --version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  fi
  
  # Normalize version string (ensure 'v' prefix)
  if [[ -n "$current_version" && ! "$current_version" =~ ^v ]]; then
    current_version="v$current_version"
  fi

  if [[ "$latest_tag" == "$current_version" ]]; then
    return 1 # No update
  fi

  # Compare versions
  if [[ "$(printf '%s\n%s' "$latest_tag" "$current_version" | sort -V | tail -1)" == "$latest_tag" ]]; then
    log "${GREEN}New version available: $latest_tag (Current: $current_version)${NC}"
    return 0 # Update available
  fi

  return 1
}

# --- Desktop Shortcut ---

create_desktop_shortcut() {
  local desktop_dir="$HOME/Desktop"
  if [[ ! -d "$desktop_dir" ]]; then
    return
  fi

  log "${BLUE}Creating desktop shortcut...${NC}"

  if [[ "$OS_TYPE" == "macOS" ]]; then
    local shortcut_path="$desktop_dir/Start Nexus Node.command"
    cat <<EOF > "$shortcut_path"
#!/bin/bash
echo "🚀 Starting Nexus Node..."
bash <(curl -fsSL $SCRIPT_URL)
EOF
    chmod +x "$shortcut_path"
    log "${GREEN}Shortcut created at: $shortcut_path${NC}"
  
  elif [[ "$OS_TYPE" == "Ubuntu" ]]; then
    local shortcut_path="$desktop_dir/nexus-node.desktop"
    cat <<EOF > "$shortcut_path"
[Desktop Entry]
Type=Application
Name=Nexus Node
Comment=Start Nexus Node
Exec=bash -c "bash <(curl -fsSL $SCRIPT_URL); exec bash"
Icon=utilities-terminal
Terminal=true
Categories=Utility;
EOF
    chmod +x "$shortcut_path"
    log "${GREEN}Shortcut created at: $shortcut_path${NC}"
  fi
}

# --- Execution ---

start_node() {
  log "${BLUE}Starting Nexus Node (ID: $NODE_ID_TO_USE)...${NC}"
  
  if [[ "$OS_TYPE" == "macOS" ]]; then
    # macOS: Open new Terminal window
    # Position calculation logic preserved for UX consistency
    local script_content="cd ~ && echo \"🚀 Starting Nexus Node...\" && nexus-network start --node-id $NODE_ID_TO_USE; echo \"Process exited.\"; read -n 1"
    
    # Escape double quotes for AppleScript string
    local applescript_cmd=${script_content//\"/\\\"}

    osascript <<EOF
tell application "Terminal"
  do script "$applescript_cmd"
  activate
end tell
EOF
    log "${GREEN}Node started in new Terminal window.${NC}"
    
  else
    # Linux: Use screen
    screen -dmS nexus_node bash -c "nexus-network start --node-id '$NODE_ID_TO_USE' >> '$LOG_FILE' 2>&1"
    sleep 2
    if screen -list | grep -q "nexus_node"; then
      log "${GREEN}Node started in screen session 'nexus_node'.${NC}"
    else
      log "${RED}Failed to start node in screen session.${NC}"
      return 1
    fi
  fi
}

main() {
  # 1. Setup Environment
  install_system_dependencies
  install_rust
  
  # 2. Install CLI & Config
  install_nexus_cli
  configure_node_id
  
  # 3. Initial Start
  create_desktop_shortcut
  cleanup_process "restart"
  start_node
  
  # 4. Monitor Loop
  log "${BLUE}Entering monitoring mode (Check every 30m)...${NC}"
  while true; do
    sleep 1800
    if check_updates; then
      log "${BLUE}Update found. Updating...${NC}"
      cleanup_process "restart"
      install_nexus_cli
      start_node
    fi
  done
}

main
