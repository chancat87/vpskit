# vpskit

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/Shell-Bash-blue.svg)](vpskit.sh)

Set up, secure and deploy on your VPS from your terminal. No third-party service, no data sent anywhere. Everything runs locally on your machine.

**Website: [vpskit.pro](https://vpskit.pro)**

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/mariusdjen/vpskit/main/vpskit.sh)
```

That's it. The script guides you through everything.

## Requirements

| System | How to run |
|--------|-----------|
| macOS | Open Terminal (built-in) and run the command above |
| Linux | Open Terminal (built-in) and run the command above |
| Windows | Install [Git Bash](https://git-scm.com/download/win) or [WSL](https://learn.microsoft.com/windows/wsl/install), then run the command above |

Your VPS must run a supported distribution (Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS, Fedora) with root access.

<details>
<summary>Windows - detailed instructions</summary>

### Git Bash

1. Install [Git for Windows](https://git-scm.com/download/win)
2. Open **Git Bash**
3. Run the command from Quick Start

### WSL

1. Enable WSL: `wsl --install` (PowerShell as admin)
2. Open the Ubuntu terminal
3. Run the command from Quick Start

### PowerShell

```powershell
curl.exe -sL https://raw.githubusercontent.com/mariusdjen/vpskit/main/vpskit.sh -o vpskit.sh
wsl bash vpskit.sh
```

</details>

## What It Does

```
$ bash vpskit.sh

========================================
  VPSKIT
  Set up and secure your server
========================================

[>] Step 1/9 : System update             [OK]
[>] Step 2/9 : User creation             [OK]
[>] Step 3/9 : SSH key setup             [OK]
[>] Step 4/9 : SSH hardening             [OK]
[>] Step 5/9 : Firewall                  [OK]
[>] Step 6/9 : Docker                    [OK]
[>] Step 7/9 : Caddy (reverse proxy)     [OK]
[>] Step 8/9 : Auto-updates              [OK]
[>] Step 9/9 : Dashboard MOTD            [OK]

=== YOUR SERVER IS READY! ===
  ssh deploy@your-server-ip
```

### Part 1: Preparation (on your machine)

| Step | Description |
|------|-------------|
| SSH key | Checks if a key exists, creates one if needed |
| Server IP | Asks for your VPS IP address |
| Key transfer | Sends your public key to the server (last password you'll type) |

Some providers (Hetzner among them) make you change the root password at the first login when the server was ordered without an SSH key. In that case log in once with `ssh root@your-server-ip`, choose a new password, then run vpskit.

### Part 2: Security and setup (on the VPS)

| Step | Description |
|------|-------------|
| System update | Updates the OS and installs git, curl, wget |
| User creation | Creates a non-root user with sudo access |
| SSH key | Copies the SSH key to the new user |
| SSH hardening | Disables root login and password authentication |
| Firewall | Enables UFW or firewalld (ports 22, 80, 443) |
| Fail2ban | Blocks IPs after 5 failed SSH attempts (1h ban) |
| Docker | Installs Docker and Docker Compose with log rotation |
| Caddy | Reverse proxy with automatic SSL (Let's Encrypt) |
| Auto-updates | Enables automatic security updates |
| Dashboard MOTD | Server status on every SSH login (CPU, RAM, disk, Docker) |

### Part 3: Post-setup

- Displays the SSH connection command
- Offers to create an SSH shortcut (`ssh vps` instead of `ssh -i ~/.ssh/key user@ip`)

## Deploy an Application

After setup, deploy your apps with one command:

Run vpskit, then choose **"Deploy an application"**.

The script asks for:
- Your Git repository URL (HTTPS or SSH, both work)
- The application name
- The domain name
- The application port (default: 3000)
- A `.env` file if needed

It automatically detects `docker-compose.yml` or `Dockerfile` in your repository.

### What deploy.sh does

1. Connects to the VPS (reuses the setup.sh session)
2. Configures GitHub SSH access if needed (multi-account support)
3. Clones the repository (or runs `git pull` if already deployed)
4. Installs the `.env` file if provided
5. Detects and runs `docker-compose.yml` or `Dockerfile`
6. Configures Caddy (reverse proxy + SSL + www redirect)
7. Verifies that the application responds

### Public and private repositories

- **Public repo** (HTTPS): cloned directly, no configuration needed
- **Private repo**: the script detects the failure, generates an SSH key and guides you step by step to add it on GitHub

### Multiple GitHub accounts

The script supports multiple GitHub accounts on the same VPS. Each account gets its own SSH key. On the first deployment, the script generates the key and walks you through adding it on GitHub. On subsequent deployments, you pick which account to use.

### Deploy a branch or tag

In interactive mode, the script lets you pick a branch or tag after entering the repository URL.

### Non-interactive mode (CI/CD)

`deploy.sh` also runs without any prompt when it gets its parameters on the command line, which is what the GitHub Actions workflow generated by **"Settings" > "Set up automatic deployment"** uses:

```bash
bash deploy.sh -app myapp -repo git@github.com:you/myapp.git -domain myapp.example.com -port 3000 -branch main
bash deploy.sh -app myapp -update
bash deploy.sh -app myapp -rollback
```

`-ip`, `-key` and `-user` default to the session saved by the setup. Private repositories need the GitHub SSH key set up once through an interactive deployment; the non-interactive mode reuses it afterwards.

### Exposed ports

Docker publishes ports with its own firewall rules, ahead of ufw or firewalld. To keep the "only 22, 80 and 443" promise, the setup configures Docker so that published ports (`-p 3000:3000`, `ports:` in a compose file) listen on `127.0.0.1` only. Caddy still reaches them on localhost. If an app really needs a public port, write `0.0.0.0:3000:3000` in its compose file; the security audit lists such ports.

### Update an existing application

Already deployed an app and want to pull the latest version? The script handles it:

Run vpskit, then choose **"Deploy" > "Update an existing application"**.

The script lists your deployed apps, you pick one, and it:
1. Saves the current commit (for rollback)
2. Runs `git pull` on the deployed branch
3. Rebuilds and restarts the Docker containers
4. Keeps your `.env` file untouched

### Rollback

If a deployment goes wrong, roll back to the previous version:

Run vpskit, then choose **"Deploy" > "Roll back to previous version"**.

The script automatically saves the commit hash before each update. Rollback restores that commit and restarts the containers.

## Server Status

Run vpskit, then choose **"Check VPS status"**.

Shows the full status of your server and all deployed applications:
- Server info: OS, uptime, CPU, RAM, disk
- Per application: Docker status, domain, port, last commit
- Docker containers summary

## Backup and Restore

### Backup

Run vpskit, then choose **"Backup / Restore"**.

For each application, the script saves:
- The `.env` file
- Docker volumes (persistent data)
- The Caddyfile (domain configuration)
- Metadata (commit, domain, port, date)

Everything is downloaded to your machine as a `vps-backup-DATE-APP.tar.gz` file.

### Restore

Run vpskit, then choose **"Backup / Restore" > "Restore"**.

## Security

Everything runs locally on your machine. No account, no cloud service, no data sent to any third party. The script connects directly to your server via SSH. Your keys stay on your machine.

## Roadmap

- Scheduled backups
- Multi-server management

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - [Marius Djen](https://github.com/mariusdjen)
