#!/bin/bash

set -e  # Exit on first error

# Auto-install toilet if not available
if ! command -v toilet &> /dev/null; then
    echo "[!] 'toilet' not found. Installing..."
    sudo apt update && sudo apt install toilet -y
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install toilet. Exiting..."
        exit 1
    fi
fi

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Display logo
function display_logo() {
    clear
    echo -e "${CYAN}"
    toilet -f smblock --filter border "WibuCrypto"
    echo -e "${NC}"
    echo -e "${GREEN}Welcome to WibuCrypto Validator Setup!${NC}"
    echo -e "${BLUE}Join us on Telegram: https://t.me/wibuairdrop142${NC}"
    echo
}

# Main menu
function main_menu() {
    while true; do
        display_logo
        echo "================================================================"
        echo "Select an option:"
        echo "1) Install and deploy node"
        echo "2) Check staking balance"
        echo "3) View broker logs"
        echo "4) Remove node"
        echo "5) Multi-GPU setup (currently unavailable)"
        echo "q) Quit"
        echo "================================================================"
        read -p "Enter choice [1/2/3/4/5/q]: " choice
        case $choice in
            1) install_node ;;
            2) check_stake_balance ;;
            3) view_broker_logs ;;
            4) remove_node ;;
            5) multi_gpu_setup ;;
            q|Q)
                echo "Goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option, try again."
                sleep 1
                ;;
        esac
    done
}

# Install and deploy node
function install_node() {
    clear
    echo "🔧 Starting node installation..."

    if [ "$EUID" -ne 0 ]; then 
        echo "❌ Please run this script with sudo."
        exit 1
    fi

    echo "🔍 Checking Docker..."
    if ! command -v docker &> /dev/null; then
        echo "📦 Installing Docker..."
        apt-get update
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        usermod -aG docker $SUDO_USER
        echo "✅ Docker installed. Please re-login for Docker group permissions to apply."
    fi

    echo "🔍 Checking NVIDIA Docker..."
    if ! command -v nvidia-docker &> /dev/null; then
        echo "📦 Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        systemctl restart docker
    fi

    echo "🔍 Checking screen..."
    command -v screen &> /dev/null || (apt-get update && apt-get install -y screen)

    echo "🔍 Checking just..."
    if ! command -v just &> /dev/null; then
        echo "📦 Installing just..."
        curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
    fi

    echo "🔄 Cloning repository..."
    if [ ! -d "boundless" ]; then
        git clone https://github.com/boundless-xyz/boundless || {
            echo "❌ Failed to clone repo. Check your internet or GitHub access."
            exit 1
        }
    fi

    cd boundless
    echo "🔁 Switching to release-0.10 branch..."
    git checkout release-0.10 || {
        echo "❌ Failed to switch branch. Check if release-0.10 exists."
        exit 1
    }

    echo "🦀 Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup update
    apt-get install -y cargo
    cargo --version

    echo "📦 Installing RISC Zero tools..."
    curl -L https://risczero.com/install | bash
    source ~/.bashrc
    rzup --version
    rzup install rust
    cargo install cargo-risczero
    rzup install cargo-risczero
    rustup update

    echo "📦 Installing bento-client..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    bento_cli --version

    echo "📦 Installing boundless-cli..."
    cargo install --locked boundless-cli
    export PATH=$PATH:/root/.cargo/bin
    source ~/.bashrc
    boundless -h

    echo "📜 Running setup.sh..."
    chmod +x ./scripts/setup.sh
    ./scripts/setup.sh

    echo "✅ All dependencies installed!"

    echo "🌐 Configure your environment:"
    read -p "Enter PRIVATE_KEY: " PRIVATE_KEY
    read -p "Enter RPC_URL (must include 'sepolia'): " RPC_URL

    if [[ "$RPC_URL" != *"sepolia"* ]]; then
        read -p "This is not a Sepolia RPC URL. Continue? (y/n): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi

    [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ] && echo "❌ Both values are required." && exit 1

    sed -i '/^PRIVATE_KEY=/d' .env.eth-sepolia 2>/dev/null
    sed -i '/^RPC_URL=/d' .env.eth-sepolia 2>/dev/null
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> .env.eth-sepolia
    echo "RPC_URL=$RPC_URL" >> .env.eth-sepolia
    source .env.eth-sepolia

    echo "🚀 Run Bento service in new terminal:"
    echo "cd $(pwd) && just bento"
    read -p "Press Enter to continue..."

    echo "⏳ Waiting for bento_cli..."
    sleep 5
    RUST_LOG=info bento_cli -c 32 | tee /tmp/bento_cli_output.log &
    BENTO_PID=$!

    while ! grep -q "image_id" /tmp/bento_cli_output.log; do
        sleep 1
    done

    echo "✅ image_id found! Setup success."
    kill $BENTO_PID
    rm /tmp/bento_cli_output.log
    read -p "Press Enter to return to menu..."
}

# Check staking balance
function check_stake_balance() {
    clear
    echo "🔍 Checking staking balance..."

    if [ ! -f "boundless/.env.eth-sepolia" ]; then
        echo "❌ Missing .env.eth-sepolia. Run install first."
        read -p "Press Enter to return..." && return
    fi

    cd boundless
    source .env.eth-sepolia

    read -p "Enter wallet address: " WALLET
    [[ ! "$WALLET" =~ ^0x[a-fA-F0-9]{40}$ ]] && echo "❌ Invalid wallet address." && read && return

    boundless account stake-balance "$WALLET" || echo "❌ Failed to fetch balance."
    read -p "Press Enter to return..."
}

# View broker logs
function view_broker_logs() {
    clear
    echo "📜 Viewing broker logs..."
    [ ! -d "boundless" ] && echo "❌ boundless directory not found." && read && return
    cd boundless

    if ! pgrep -f "just broker" > /dev/null; then
        read -p "Broker not running. Start it? (y/n): " start
        [[ "$start" =~ ^[Yy]$ ]] && echo "Run in new terminal: cd $(pwd) && just broker" && read
        return
    fi

    just broker logs
    read -p "Press Enter to return..."
}

# Remove node
function remove_node() {
    clear
    echo "🧹 Removing node..."

    read -p "Are you sure? This will delete everything. (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Cancelled." && read && return

    [ ! -d "boundless" ] && echo "❌ No boundless directory." && read && return
    cd boundless
    pgrep -f "just broker" > /dev/null && just broker down
    just broker clean || echo "⚠️ Failed cleaning, continuing..."
    cd ..
    rm -rf boundless
    echo "✅ Node removed."
    read -p "Press Enter to return..."
}

# Multi-GPU setup placeholder
function multi_gpu_setup() {
    clear
    echo "⚙️ Multi-GPU setup (coming soon)"
    [ ! -d "boundless" ] && echo "❌ No boundless directory." && read && return
    cd boundless
    if ! command -v nvidia-smi &> /dev/null; then
        echo "❌ NVIDIA driver not found."
        read && return
    fi
    nvidia-smi -L
    read -p "Press Enter to return..."
}

# Run main menu
main_menu
