# Nexus Node Deployment Script

This script automates the deployment and management of a Nexus Node on macOS and Ubuntu. It handles dependency installation, node configuration, process management, and automatic updates.

## Features

- **Automated Setup**: Installs all required dependencies (Rust, CMake, Protobuf, etc.).
- **Auto-Updates**: Monitors for new Nexus CLI versions every 30 minutes and updates automatically.
- **Process Management**: Gracefully handles start, stop, and restarts.
- **Cross-Platform**: Supports macOS (runs in a new Terminal window) and Ubuntu (runs in a `screen` session).
- **Resilient**: Auto-rotates logs and handles process cleanup.

## Quick Start

Run the following command to install and start your Nexus Node:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Xiaofei-Z/nex/main/nexus.sh)
```

> **Note**: This command downloads and runs the `nexus.sh` script directly from the repository.

## Configuration

### Non-Interactive Mode (Recommended for Scripts)

You can provide your Node ID via an environment variable to skip the interactive prompt:

```bash
export NEXUS_NODE_ID="your-node-id"
bash <(curl -fsSL https://raw.githubusercontent.com/Xiaofei-Z/nex/main/nexus.sh)
```

### Interactive Mode

If no environment variable is set, the script will prompt you to enter a Node ID during the first run. It will verify if a valid ID is already saved in `~/.nexus/config.json`.

## Management

- **Logs**: Logs are stored at `~/nexus.log`.
- **Stop**: Press `Ctrl+C` in the script terminal to stop the monitoring process. The node itself might continue running until you run the cleanup.
- **Manual Cleanup**: If you need to kill all Nexus processes manually:
    ```bash
    pkill -f nexus-cli
    pkill -f nexus-network
    screen -X -S nexus_node quit  # Linux only
    ```

## Requirements

- **OS**: macOS or Ubuntu Linux.
- **Permissions**: `sudo` access is required for installing dependencies on Linux.

## License

MIT
