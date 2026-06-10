🚀 Pro-Spec Ubuntu Infrastructure Bootstrapper
A streamlined, declarative, and idempotent system initialization environment that transforms a bare Ubuntu/Debian server into a hardened, Docker-ready development environment in under 60 seconds

This project moves away from passive, bloated configuration files, serving as an automated Infrastructure-as-Code (IaC) baseline

# 🌟 Added Value & Core Philosophy

## The "Single Stitch" Include Pattern
Unlike traditional scripts that repeatedly append blocks of text to your ~/.bashrc, this suite uses a modular approach. It injects exactly one declaration into your shell profile that points to a managed alias file (~/.bash_aliases_pro). This ensures zero configuration rot even after multiple runs

## Modular Architecture
The suite is broken down into dedicated modules for better maintenance and fault isolation:
- 01_privileges.sh: Securely maps passwordless sudo access.
- 02_environment.sh: Detects OS matrix and prepares local bin paths.
- 03_tools.sh: Deploys the Master Tool Suite (Docker CE, Zellij, btop, fzf, etc.).
- 04_optimization.sh: Injects multi-threaded zstd zRAM tuning for high-speed swap performance.
- 05_stitch.sh: Links your universal alias repository to the local system.

## CI/DI Loopback Mechanism
The suite includes a unique Universal Sync feature. Every time you run the update command, the system performs a "loopback" check:
- It pulls the latest changes from your global alias repository. 
- It compares your local .env with the synced .env.template to warn you of new required keys.
- It refreshes your dynamic cheatsheets in real-time.

## 📊 Process Flow - System Initialization Flow

     [ USER ]
        |
        v
     [init_pro.sh] <--- (🪤 Traps Errors & Starts Telemetry)
      |
      +-----+-----+-----------------------+
      |           |                       |
     [Privs ]    [Env Test ]             [Repos & Tools ]
      |           |                       |
      v           v                       v
     (Sudo)    (Ubuntu/Debian?)    (Docker/Zellij/Btop)
      |           |                       |
      +-----+-----+-----------------------+
         |
         v
     [.bashrc Stitch] <--- (Links Repo to Home)
     The Ongoing Loopback (Universal Sync)

🚩 Synchronization

     ( Admin Stickman )
         O
        /|\  --- "update" command ---> [ Local VM ]
        / \                             |
                                        | (Step 1: Git Pull Repo)
                                        v
                                [ Repository Repo ]
                                /        |        \
                       [.env.temp]  [.secrets.temp]  [.custom_bashrc]
                                \        |        /
                                 [ VM SYNCED ✅ ]

# 🚀 Installation

## The One-Liner (Fastest)
Run this command to bootstrap the entire environment and repository structure automatically:
```
curl -sSL https://raw.githubusercontent.com/alwazw/.bashrc/main/bootstrap.sh | bash
```
## Pull & Execute
If you prefer to review the files before running the orchestration:

1- Manual Pull & Execute
```
# Clone the Repository:
git clone https://github.com/alwazw/ubuntu-customz

# Navigate and Grant Permissions:
cd ubuntu-customz
sudo chmod +x init_pro.sh

# Execute the Orchestrator:
./init_pro.sh

```
2- Refresh Session
```
source ~/.bashrc
```

# 🛠 Included in Toolset:
- Containerization: Official Docker Engine CE and Compose V2
- Performance: btop, htop, and zRAM optimization
- Security: UFW (Ports 22, 80, 443), Fail2Ban, and Etckeeper tracking for /etc
- Productivity: Zellij multiplexer, fzf, bat, and ripgrep