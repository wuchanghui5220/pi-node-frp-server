# FRP Server Deployment Script

A one-click deployment script for setting up a secure [frp](https://github.com/fatedier/frp) (Fast Reverse Proxy) server on AWS or other Linux servers. This script automates the entire deployment process, making it easy to establish a reliable and secure reverse proxy.

## Features

- 🔒 **Enhanced Security**: Implements TLS encryption, random token generation, and proper firewall configurations
- 🚀 **Fully Automated**: One command to install and configure everything
- 🔄 **Auto-monitoring**: Built-in service monitoring and auto-restart capability
- 🌐 **Multi-platform Support**: Works with various firewall systems (UFW, FirewallD, iptables)
- 📋 **Client Configuration**: Automatically generates Windows client configuration examples
- 🔧 **Port Control**: Configures secure port ranges for proxy services (31400-31409)
- 📊 **Logging**: Proper logging setup with rotation

## Prerequisites

- Linux server (preferably AWS EC2 instance)
- Root or sudo privileges
- Internet connection for downloading packages
- Open ports in your security group or firewall (7000 and 31400-31409)

## Quick Install

Connect to your server via SSH and run:

```bash
wget -O frp-deploy.sh https://raw.githubusercontent.com/yourusername/frp-server-deploy/main/frp-deploy.sh
chmod +x frp-deploy.sh
sudo bash frp-deploy.sh
```

## What Does This Script Do?

1. Installs the latest version of frp server
2. Generates a secure random token for authentication
3. Configures TLS encryption for all connections
4. Creates and starts a systemd service for automatic startup
5. Configures firewall rules to allow necessary connections
6. Sets up a monitoring service that automatically restarts frp if it crashes
7. Generates a comprehensive configuration guide for Windows clients

## Post-Installation

After installation completes, the script will:

1. Create a systemd service called `frps` that starts automatically on boot
2. Generate a config file at `~/frpserverinfo.txt` with all the details you need for client setup
3. Open ports 7000 and 31400-31409 in the firewall

## Client Setup

The generated `frpserverinfo.txt` file contains detailed instructions for setting up Windows clients. It includes:

- Server connection details
- Authentication token
- Example configuration for Windows
- Download links for necessary software
- Security recommendations

## Security Notes

This script implements several security best practices:

- TLS encryption for all communication
- Random token-based authentication
- Restricted port range (31400-31409)
- Limited error reporting to clients
- Regular service monitoring

## AWS-Specific Setup

If you're using AWS EC2:

1. Make sure your security group allows inbound traffic on port 7000 (for frp connection)
2. Allow inbound traffic on ports 31400-31409 (for your services)
3. Follow standard AWS security best practices

## Troubleshooting

- **Service doesn't start**: Check logs with `journalctl -u frps`
- **Connection issues**: Verify firewall settings with `iptables -L` or equivalent
- **Client can't connect**: Ensure security groups/network ACLs allow traffic

## Maintenance

- Update the token periodically by editing `/etc/frp/frps.ini`
- Keep frp updated by running the script again (it will download the latest version)
- Check logs in `/var/log/frp/` for any issues

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- [fatedier/frp](https://github.com/fatedier/frp) for the excellent reverse proxy tool
