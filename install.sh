#!/bin/bash
#
# AtherOps Agent Installer
# Usage: API_KEY=your-key PORTAL_URL=https://portal.atherops.com bash install.sh
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
PORTAL_URL="${PORTAL_URL:-http://localhost:3000}"
REGISTRATION_KEY="${REGISTRATION_KEY:-}"
AGENT_VERSION="${AGENT_VERSION:-}"

# GitHub release URL (public releases repo)
GITHUB_REPO="${GITHUB_REPO:-AtherOps/atherops-agent-release}"
RELEASE_URL=""  # Will be set based on detected platform

# ============================================================================
# CONSTANTS
# ============================================================================
AGENT_NAME="atherops-agent"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/atherops}"
DATA_DIR="${DATA_DIR:-/var/lib/atherops-agent}"
LOG_DIR="${LOG_DIR:-/var/log/atherops}"
SERVICE_FILE="/etc/systemd/system/atherops-agent.service"

# For development without sudo
if [ -z "$SUDO_USER" ] && [ "$EUID" -ne 0 ]; then
    INSTALL_DIR="$HOME/.local/bin"
    CONFIG_DIR="$HOME/.config/atherops"
    DATA_DIR="$HOME/.local/share/atherops-agent"
    LOG_DIR="$HOME/.local/share/atherops-agent/logs"
    SERVICE_FILE="$HOME/.config/systemd/user/atherops-agent.service"
    USE_USER_MODE=true
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ -n "$DEBUG" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

check_root() {
    if [ "$USE_USER_MODE" = true ]; then
        log_warn "Running in user mode (no sudo)"
        return
    fi
    
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        log_info "Or set USE_USER_MODE=true for user installation"
        exit 1
    fi
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        VERSION=$(uname -r)
    fi
    log_info "Detected OS: $OS $VERSION"
}

detect_platform() {
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    
    case $arch in
        x86_64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) log_error "Unsupported architecture: $arch"; exit 1 ;;
    esac
    
    local binary_name="atherops-agent-${os}-${arch}"
    [ "$os" = "windows" ] && binary_name="${binary_name}.exe"
    
    # Fetch latest version from GitHub if not specified
    if [ -z "$AGENT_VERSION" ]; then
        log_info "Fetching latest version from GitHub..."
        AGENT_VERSION=$(curl -s https://api.github.com/repos/${GITHUB_REPO}/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        if [ -z "$AGENT_VERSION" ]; then
            log_error "Failed to fetch latest version from GitHub"
            exit 1
        fi
        log_info "Latest version: $AGENT_VERSION"
    fi
    
    RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/${AGENT_VERSION}/${binary_name}"
    
    log_debug "Platform: ${os}-${arch}"
    log_debug "Release URL: $RELEASE_URL"
}

get_public_ip() {
    local ip=""
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) || \
    ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
    ip="unknown"
    echo "$ip"
}

get_private_ip() {
    local ip=""
    ip=$(hostname -I 2>/dev/null | awk '{print $1}') || \
    ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}') || \
    ip=$(ifconfig 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}' | cut -d: -f2) || \
    ip="unknown"
    echo "$ip"
}

get_hostname() {
    hostname -f 2>/dev/null || hostname
}

# ============================================================================
# REGISTRATION
# ============================================================================

register_agent() {
    log_info "Registering agent with portal at $PORTAL_URL..."
    
    local hostname=$(get_hostname)
    local public_ip=$(get_public_ip)
    local private_ip=$(get_private_ip)
    local os_info="$OS $VERSION"
    local arch=$(uname -m)
    
    log_info "  Hostname:   $hostname"
    log_info "  Public IP:  $public_ip"
    log_info "  Private IP: $private_ip"
    log_info "  OS:         $os_info"
    log_info "  Arch:       $arch"
    
    # Create JSON payload
    local payload=$(cat <<EOF
{
    "hostname": "$hostname",
    "public_ip": "$public_ip",
    "private_ip": "$private_ip",
    "os": "$os_info",
    "arch": "$arch",
    "agent_version": "$AGENT_VERSION"
}
EOF
)
    
    log_debug "Registration payload: $payload"
    
    # Send registration request to portal
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -H "X-Registration-Key: $REGISTRATION_KEY" \
        -d "$payload" \
        "$PORTAL_URL/api/v1/agents/register" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    log_debug "HTTP Code: $http_code"
    log_debug "Response: $body"
    
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        log_error "Registration failed with HTTP $http_code"
        log_error "Response: $body"
        exit 1
    fi
    
    log_info "✓ Registration successful!"
    echo "$body"
}

# ============================================================================
# INSTALLATION
# ============================================================================

create_directories() {
    log_info "Creating directories..."
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$DATA_DIR/buffer"
    log_info "  Config: $CONFIG_DIR"
    log_info "  Data:   $DATA_DIR"
    log_info "  Logs:   $LOG_DIR"
}

download_agent() {
    log_info "Downloading agent binary from GitHub..."
    log_info "  URL: $RELEASE_URL"
    
    # Create install directory if it doesn't exist
    mkdir -p "$INSTALL_DIR"
    
    if ! curl -L -f -o "$INSTALL_DIR/$AGENT_NAME" "$RELEASE_URL"; then
        log_error "Failed to download agent binary"
        log_error "URL: $RELEASE_URL"
        exit 1
    fi
    
    chmod +x "$INSTALL_DIR/$AGENT_NAME"
    log_info "✓ Agent binary installed to $INSTALL_DIR/$AGENT_NAME"
}

create_config() {
    local registration_data="$1"
    
    log_info "Creating configuration file..."
    
    # Parse registration response using grep (more portable than jq)
    local agent_id=$(echo "$registration_data" | grep -o '"agent_id":"[^"]*"' | cut -d'"' -f4)
    local api_key=$(echo "$registration_data" | grep -o '"api_key":"[^"]*"' | cut -d'"' -f4)
    local metrics_url=$(echo "$registration_data" | grep -o '"metrics_endpoint":"[^"]*"' | cut -d'"' -f4)
    local interval=$(echo "$registration_data" | grep -o '"interval":"[^"]*"' | cut -d'"' -f4)
    local heartbeat_url=$(echo "$registration_data" | grep -o '"heartbeat_endpoint":"[^"]*"' | cut -d'"' -f4)
    
    # Set defaults if not provided
    if [ -z "$agent_id" ]; then
        agent_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "agent-$(date +%s)")
    fi
    interval=${interval:-"30s"}
    metrics_url=${metrics_url:-"$PORTAL_URL/api/v1/metrics"}
    
    log_info "  Agent ID:       $agent_id"
    log_info "  Metrics URL:    $metrics_url"
    log_info "  Interval:       $interval"
    
    # Create config.yaml
    cat > "$CONFIG_DIR/config.yaml" <<EOF
# AtherOps Agent Configuration
# Auto-generated during installation on $(date)

metrics:
  # Backend server configuration
  server_url: "$metrics_url"
  api_key: "$api_key"
  
  # Agent identification
  agent_id: "$agent_id"
  
  # Collection settings
  interval: "$interval"
  enable_gzip: true
  
  # Export format configuration
  export_formats: ["json"]
  tsdb_naming: false
  include_metadata: false
  
  # Reliability settings
  max_retries: 5
  retry_delay: "10s"
  
  # Local buffering
  buffer_path: "$DATA_DIR/buffer"
EOF

    # Add heartbeat configuration if provided
    if [ -n "$heartbeat_url" ]; then
        cat >> "$CONFIG_DIR/config.yaml" <<EOF
  
  # Heartbeat configuration
  heartbeat:
    enabled: true
    websocket_url: "$heartbeat_url"
    interval: "30s"
    timeout: "10s"
    retry_interval: "5s"
EOF
    else
        cat >> "$CONFIG_DIR/config.yaml" <<EOF
  
  # Heartbeat configuration
  heartbeat:
    enabled: false
EOF
    fi
    
    chmod 600 "$CONFIG_DIR/config.yaml"
    log_info "✓ Configuration file created at $CONFIG_DIR/config.yaml"
}

create_systemd_service() {
    log_info "Creating systemd service..."
    
    if [ "$USE_USER_MODE" = true ]; then
        # User mode service
        mkdir -p "$(dirname "$SERVICE_FILE")"
        
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AtherOps Monitoring Agent (User Mode)
Documentation=https://github.com/AtherOps/atherops-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/$AGENT_NAME --config $CONFIG_DIR/config.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload
        log_info "✓ User systemd service created"
    else
        # System mode service
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AtherOps Monitoring Agent
Documentation=https://github.com/AtherOps/atherops-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/$AGENT_NAME --config $CONFIG_DIR/config.yaml
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=atherops-agent

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$DATA_DIR $LOG_DIR

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl daemon-reload
        log_info "✓ System systemd service created"
    fi
}

start_agent() {
    log_info "Enabling and starting agent service..."
    
    if [ "$USE_USER_MODE" = true ]; then
        systemctl --user enable atherops-agent
        systemctl --user start atherops-agent
        
        sleep 2
        
        if systemctl --user is-active --quiet atherops-agent; then
            log_info "✓ Agent service started successfully!"
        else
            log_error "Agent service failed to start"
            log_info "Check logs with: journalctl --user -u atherops-agent -f"
            exit 1
        fi
    else
        systemctl enable atherops-agent
        systemctl start atherops-agent
        
        sleep 2
        
        if systemctl is-active --quiet atherops-agent; then
            log_info "✓ Agent service started successfully!"
            
            # Add user to systemd-journal group to view all logs
            if [ -n "$SUDO_USER" ]; then
                log_info "Adding $SUDO_USER to systemd-journal group for log access..."
                usermod -aG systemd-journal "$SUDO_USER" 2>/dev/null || log_warn "Could not add user to systemd-journal group"
            fi
        else
            log_error "Agent service failed to start"
            log_info "Check logs with: journalctl -u atherops-agent -f"
            exit 1
        fi
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    log_info "=================================================="
    log_info "  AtherOps Agent Installation"
    log_info "=================================================="
    echo ""
    
    # Validate registration key
    if [ -z "$REGISTRATION_KEY" ]; then
        log_error "Registration key not provided!"
        log_info "Usage: REGISTRATION_KEY=your-key bash install.sh"
        log_info "   Or: export REGISTRATION_KEY=your-key && bash install.sh"
        exit 1
    fi
    
    # Pre-flight checks
    check_root
    detect_os
    detect_platform
    
    # Check if agent is already installed
    if [ "$USE_USER_MODE" = true ]; then
        if systemctl --user is-active --quiet atherops-agent 2>/dev/null; then
            log_warn "Agent is already running. Stopping it..."
            systemctl --user stop atherops-agent
        fi
    else
        if systemctl is-active --quiet atherops-agent 2>/dev/null; then
            log_warn "Agent is already running. Stopping it..."
            systemctl stop atherops-agent
        fi
    fi
    
    # Register with portal
    registration_data=$(register_agent)
    
    # Install agent
    create_directories
    download_agent
    create_config "$registration_data"
    create_systemd_service
    start_agent
    
    echo ""
    log_info "=================================================="
    log_info "  Installation Complete!"
    log_info "=================================================="
    echo ""
    
    if [ "$USE_USER_MODE" = true ]; then
        log_info "Status:  systemctl --user status atherops-agent"
        log_info "Logs:    journalctl --user -u atherops-agent -f"
        log_info "Stop:    systemctl --user stop atherops-agent"
        log_info "Restart: systemctl --user restart atherops-agent"
    else
        log_info "Status:  sudo systemctl status atherops-agent"
        log_info "Logs:    sudo journalctl -u atherops-agent -f"
        log_info "Stop:    sudo systemctl stop atherops-agent"
        log_info "Restart: sudo systemctl restart atherops-agent"
    fi
    
    log_info "Config:  $CONFIG_DIR/config.yaml"
    echo ""
}

main
