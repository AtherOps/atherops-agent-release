# AtherOps Agent

Open-source monitoring agent for collecting system metrics and sending them to the AtherOps portal.

## 🚀 Quick Installation

### Ubuntu/Debian (with portal registration)

```bash
REGISTRATION_KEY=your-key PORTAL_URL=https://portal.atherops.com \
  bash <(curl -sfL https://raw.githubusercontent.com/AtherOps/atherops-agent-release/main/install.sh)
```

### Manual Installation

```bash
# Download latest version
VERSION=$(curl -s https://api.github.com/repos/AtherOps/atherops-agent-release/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -LO https://github.com/AtherOps/atherops-agent-release/releases/download/${VERSION}/atherops-agent-linux-amd64

# Verify checksum
curl -LO https://github.com/AtherOps/atherops-agent-release/releases/download/${VERSION}/SHA256SUMS
sha256sum -c SHA256SUMS --ignore-missing

# Install
chmod +x atherops-agent-linux-amd64
sudo mv atherops-agent-linux-amd64 /usr/local/bin/atherops-agent

# Run with registration
sudo atherops-agent --register
```

## 📦 System Requirements

- **OS**: Ubuntu 18.04+, Debian 9+, or any systemd-based Linux
- **Architecture**: x86_64 (AMD64)
- **Kernel**: 3.10+

## 🔧 Usage

### Service Management

```bash
# Check status
sudo systemctl status atherops-agent

# View logs
sudo journalctl -u atherops-agent -f

# Restart service
sudo systemctl restart atherops-agent

# Stop service
sudo systemctl stop atherops-agent
```

### Configuration

Configuration file: `/etc/atherops/config.yaml`

```yaml
metrics:
  server_url: "https://portal.atherops.com/api/v1/ingest/prometheus"
  agent_id: "your-agent-id"
  api_key: "your-api-key"
  interval: "30s"
  enable_gzip: true
  
  heartbeat:
    enabled: true
    websocket_url: "wss://portal.atherops.com/v1/agents/heartbeat"
    interval: "30s"
```

## 🔄 Self-Update Feature

The agent automatically checks for updates during heartbeat communication. When a new version is available:

1. Portal notifies the agent via heartbeat
2. Agent downloads and verifies the new binary
3. Binary is replaced atomically
4. Service restarts automatically (via systemd)
5. Agent resumes operation with new version

### Manual Update

```bash
# Download latest install script and run
bash <(curl -sfL https://raw.githubusercontent.com/AtherOps/atherops-agent-release/main/install.sh)
```

## 🗑️ Uninstallation

### Complete Removal

```bash
bash <(curl -sfL https://raw.githubusercontent.com/AtherOps/atherops-agent-release/main/uninstall.sh)
```

### Keep Data and Logs

```bash
bash <(curl -sfL https://raw.githubusercontent.com/AtherOps/atherops-agent-release/main/uninstall.sh) --keep-data
```

### Force Uninstall (no prompts)

```bash
bash <(curl -sfL https://raw.githubusercontent.com/AtherOps/atherops-agent-release/main/uninstall.sh) --force
```

## 📂 File Locations

### System Mode (default with sudo)

- **Binary**: `/usr/local/bin/atherops-agent`
- **Config**: `/etc/atherops/config.yaml`
- **Data**: `/var/lib/atherops-agent/`
- **Logs**: `/var/log/atherops/`
- **Service**: `/etc/systemd/system/atherops-agent.service`

### User Mode (without sudo)

- **Binary**: `$HOME/.local/bin/atherops-agent`
- **Config**: `$HOME/.config/atherops/config.yaml`
- **Data**: `$HOME/.local/share/atherops-agent/`
- **Logs**: `$HOME/.local/share/atherops-agent/logs/`
- **Service**: `$HOME/.config/systemd/user/atherops-agent.service`

## 🛡️ Security

- Binaries are stripped and built with `-trimpath` for minimal attack surface
- SHA256 checksums provided for all releases
- Service runs with security hardening (NoNewPrivileges, ProtectSystem, etc.)
- Credentials stored with 600 permissions

## 📊 Metrics Collected

- **CPU**: Usage, cores, frequency
- **Memory**: Total, used, available, swap
- **Disk**: Usage, I/O stats, mount points
- **Network**: Traffic, connections, interfaces
- **System**: Load average, uptime, processes

## 🔗 Links

- **Documentation**: https://docs.atherops.com
- **Portal**: https://portal.atherops.com
- **Support**: support@atherops.com

## 📝 License

Proprietary - © 2025 AtherOps. All rights reserved.
