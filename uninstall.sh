#!/bin/bash
#
# AtherOps Agent Uninstaller
# Usage: bash uninstall.sh [--force]
#

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
AGENT_NAME="atherops-agent"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${CONFIG_DIR:-/etc/atherops}"
DATA_DIR="${DATA_DIR:-/var/lib/atherops-agent}"
LOG_DIR="${LOG_DIR:-/var/log/atherops}"
SERVICE_FILE="/etc/systemd/system/atherops-agent.service"

# For user mode detection
if [ -z "$SUDO_USER" ] && [ "$EUID" -ne 0 ]; then
    INSTALL_DIR="$HOME/.local/bin"
    CONFIG_DIR="$HOME/.config/atherops"
    DATA_DIR="$HOME/.local/share/atherops-agent"
    LOG_DIR="$HOME/.local/share/atherops-agent/logs"
    SERVICE_FILE="$HOME/.config/systemd/user/atherops-agent.service"
    USE_USER_MODE=true
fi

# Parse arguments
FORCE=false
KEEP_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --keep-data)
            KEEP_DATA=true
            shift
            ;;
        -h|--help)
            echo "AtherOps Agent Uninstaller"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force       Skip confirmation prompts"
            echo "  --keep-data   Keep data directory (credentials and logs)"
            echo "  -h, --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

confirm() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    local prompt="$1"
    local response
    
    while true; do
        echo -ne "${YELLOW}$prompt (y/n): ${NC}"
        read -r response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

check_root() {
    if [ "$USE_USER_MODE" = true ]; then
        log_info "Running in user mode (no sudo)"
        return
    fi
    
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# ============================================================================
# UNINSTALL FUNCTIONS
# ============================================================================

stop_and_disable_service() {
    log_info "Stopping and disabling agent service..."
    
    if [ "$USE_USER_MODE" = true ]; then
        if systemctl --user is-active --quiet atherops-agent 2>/dev/null; then
            systemctl --user stop atherops-agent
            log_info "✓ Service stopped"
        else
            log_warn "Service was not running"
        fi
        
        if systemctl --user is-enabled --quiet atherops-agent 2>/dev/null; then
            systemctl --user disable atherops-agent
            log_info "✓ Service disabled"
        fi
    else
        if systemctl is-active --quiet atherops-agent 2>/dev/null; then
            systemctl stop atherops-agent
            log_info "✓ Service stopped"
        else
            log_warn "Service was not running"
        fi
        
        if systemctl is-enabled --quiet atherops-agent 2>/dev/null; then
            systemctl disable atherops-agent
            log_info "✓ Service disabled"
        fi
    fi
}

remove_service_file() {
    log_info "Removing systemd service file..."
    
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        log_info "✓ Service file removed: $SERVICE_FILE"
        
        if [ "$USE_USER_MODE" = true ]; then
            systemctl --user daemon-reload
        else
            systemctl daemon-reload
        fi
        log_info "✓ Systemd daemon reloaded"
    else
        log_warn "Service file not found: $SERVICE_FILE"
    fi
}

remove_binary() {
    log_info "Removing agent binary..."
    
    if [ -f "$INSTALL_DIR/$AGENT_NAME" ]; then
        rm -f "$INSTALL_DIR/$AGENT_NAME"
        log_info "✓ Binary removed: $INSTALL_DIR/$AGENT_NAME"
    else
        log_warn "Binary not found: $INSTALL_DIR/$AGENT_NAME"
    fi
}

remove_config() {
    log_info "Removing configuration directory..."
    
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        log_info "✓ Configuration removed: $CONFIG_DIR"
    else
        log_warn "Configuration directory not found: $CONFIG_DIR"
    fi
}

remove_data() {
    if [ "$KEEP_DATA" = true ]; then
        log_warn "Keeping data directory as requested: $DATA_DIR"
        return
    fi
    
    log_info "Removing data directory..."
    
    if [ -d "$DATA_DIR" ]; then
        if confirm "Remove data directory (includes credentials and buffer)? $DATA_DIR"; then
            rm -rf "$DATA_DIR"
            log_info "✓ Data removed: $DATA_DIR"
        else
            log_warn "Skipping data directory removal"
        fi
    else
        log_warn "Data directory not found: $DATA_DIR"
    fi
}

remove_logs() {
    if [ "$KEEP_DATA" = true ]; then
        log_warn "Keeping log directory as requested: $LOG_DIR"
        return
    fi
    
    log_info "Removing log directory..."
    
    if [ -d "$LOG_DIR" ]; then
        if confirm "Remove log directory? $LOG_DIR"; then
            rm -rf "$LOG_DIR"
            log_info "✓ Logs removed: $LOG_DIR"
        else
            log_warn "Skipping log directory removal"
        fi
    else
        log_warn "Log directory not found: $LOG_DIR"
    fi
}

unregister_agent() {
    log_info "Checking for agent credentials to unregister..."
    
    local creds_file="$DATA_DIR/credentials.json"
    
    if [ ! -f "$creds_file" ]; then
        log_warn "Credentials file not found, skipping portal unregistration"
        return
    fi
    
    # Try to unregister from portal if credentials exist
    if [ -x "$INSTALL_DIR/$AGENT_NAME" ]; then
        log_info "Attempting to unregister from portal..."
        if "$INSTALL_DIR/$AGENT_NAME" --unregister 2>/dev/null; then
            log_info "✓ Successfully unregistered from portal"
        else
            log_warn "Could not unregister from portal (agent may already be removed)"
        fi
    else
        log_warn "Agent binary not found, skipping portal unregistration"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           AtherOps Agent Uninstaller                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    
    # Show what will be removed
    echo "The following will be removed:"
    echo "  - Service: $SERVICE_FILE"
    echo "  - Binary: $INSTALL_DIR/$AGENT_NAME"
    echo "  - Config: $CONFIG_DIR"
    if [ "$KEEP_DATA" = false ]; then
        echo "  - Data: $DATA_DIR"
        echo "  - Logs: $LOG_DIR"
    else
        echo "  - Data: $DATA_DIR (will be kept)"
        echo "  - Logs: $LOG_DIR (will be kept)"
    fi
    echo ""
    
    if ! confirm "Proceed with uninstallation?"; then
        log_info "Uninstallation cancelled"
        exit 0
    fi
    
    echo ""
    log_info "Starting uninstallation..."
    echo ""
    
    # Perform uninstallation steps
    stop_and_disable_service
    unregister_agent
    remove_service_file
    remove_binary
    remove_config
    remove_data
    remove_logs
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         AtherOps Agent Successfully Uninstalled            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [ "$KEEP_DATA" = true ]; then
        log_info "Note: Data directory preserved at: $DATA_DIR"
    fi
    
    if [ "$USE_USER_MODE" = true ]; then
        log_info "To reinstall, run the installation script again"
    else
        log_info "To reinstall, run: curl -sSL https://portal.atherops.com/agent/install.sh | sudo bash"
    fi
    
    echo ""
}

# Run main function
main "$@"
