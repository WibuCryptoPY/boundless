#!/bin/bash

# Auto-install toilet if not available
if ! command -v toilet &> /dev/null; then
    echo "[!] 'toilet' not found. Installing..."
    sudo apt update && sudo apt install toilet -y
    if [ $? -ne 0 ]; then
        echo "Failed to install toilet. Exiting..."
        exit 1
    fi
fi

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Display ASCII logo
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
        echo "Press Ctrl + C to exit."
        echo "Please choose an action:"
        echo "1) Install and deploy node"
        echo "2) View staking balance"
        echo "3) View broker logs"
        echo "4) Remove node"
        echo "5) Multi-GPU version (currently unavailable)"
        echo "q) Quit script"
        echo "================================================================"
        read -p "Enter choice [1/2/3/4/5/q]: " choice
        case $choice in
            1) install_node ;;
            2) check_stake_balance ;;
            3) view_broker_logs ;;
            4) remove_node ;;
            5) multi_gpu_setup ;;
            q|Q)
                echo "Thanks for using, goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option, please try again."
                sleep 2
                ;;
        esac
    done
}

# Function: Install and deploy node
function install_node() {
    clear
    echo "Starting node installation..."

    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script with sudo."
        exit 1
    fi

    echo "Checking Docker..."
    if ! command -v docker &> /dev/null; then
        echo "Installing Docker..."
        apt-get update
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        usermod -aG docker $SUDO_USER
        echo "Docker installed. Please log out and back in to activate group changes."
    fi

    echo "Checking NVIDIA Docker..."
    if ! command -v nvidia-docker &> /dev/null; then
        echo "Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        systemctl restart docker
        echo "NVIDIA Container Toolkit installed."
    fi

    echo "Checking screen..."
    if ! command -v screen &> /dev/null; then
        echo "Installing screen..."
        apt-get update
        apt-get install -y screen
        [ $? -ne 0 ] && echo "Screen install failed. Please install manually." && exit 1
    fi

    echo "Checking just..."
    if ! command -v just &> /dev/null; then
        echo "Installing just..."
        curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
        [ $? -ne 0 ] && echo "just install failed." && exit 1
    fi

    echo "Cloning repository..."
    [ ! -d "boundless" ] && git clone https://github.com/boundless-xyz/boundless || exit 1
    cd boundless || exit 1
    git checkout release-0.10 || exit 1

    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup update || exit 1
    apt-get install -y cargo || exit 1
    cargo --version || exit 1

    echo "Installing rzup..."
    curl -L https://risczero.com/install | bash
    source ~/.bashrc
    rzup --version || exit 1
    rzup install rust || exit 1

    echo "Installing cargo-risczero..."
    cargo install cargo-risczero
    rzup install cargo-risczero || exit 1
    rustup update || exit 1

    echo "Installing bento-client..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    bento_cli --version || exit 1

    echo "Installing boundless-cli..."
    cargo install --locked boundless-cli
    export PATH=$PATH:/root/.cargo/bin
    source ~/.bashrc
    boundless -h || exit 1

    echo "Running setup.sh..."
    chmod +x ./scripts/setup.sh && ./scripts/setup.sh || exit 1

    echo "All dependencies installed. Log out & log in again to apply Docker permissions."

    echo "Enter your PRIVATE_KEY and Sepolia RPC URL from Alchemy:"
    read -p "PRIVATE_KEY: " PRIVATE_KEY
    read -p "RPC_URL (must include 'sepolia'): " RPC_URL

    if [[ "$RPC_URL" != *"sepolia"* ]]; then
        read -p "This is not a Sepolia URL. Continue anyway? (y/n): " confirm
        [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 1
    fi

    [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ] && echo "Both fields are required." && exit 1

    sed -i '/^PRIVATE_KEY=/d' .env.eth-sepolia 2>/dev/null
    sed -i '/^RPC_URL=/d' .env.eth-sepolia 2>/dev/null

    echo "Writing environment variables..."
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> .env.eth-sepolia
    echo "RPC_URL=$RPC_URL" >> .env.eth-sepolia
    source .env.eth-sepolia

    echo "Start Bento service in a new terminal:"
    echo "cd $(pwd) && just bento"
    read -p "Press Enter to continue..."

    echo "Waiting 5 seconds before running bento_cli..."
    sleep 5
    RUST_LOG=info bento_cli -c 32 | tee /tmp/bento_cli_output.log &
    BENTO_PID=$!

    echo "Waiting for image_id..."
    while ! grep -q "image_id" /tmp/bento_cli_output.log; do sleep 1; done

    echo "Success! image_id found."
    kill $BENTO_PID
    rm /tmp/bento_cli_output.log
    echo "Installation complete!"
    read -p "Press Enter to return to menu..."
}

# View staking balance
function check_stake_balance() {
    clear
    echo "Checking staking balance..."

    if [ ! -f "boundless/.env.eth-sepolia" ]; then
        echo "Missing .env.eth-sepolia. Run option 1 first."
        read -p "Press Enter to return..." && return
    fi

    cd boundless
    source .env.eth-sepolia
    [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ] && echo "Environment variables not set." && read && return

    read -p "Enter wallet address: " WALLET_ADDRESS
    [[ ! "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]] && echo "Invalid wallet address format." && read && return

    boundless account stake-balance "$WALLET_ADDRESS" || echo "Error fetching balance."
    read -p "Press Enter to return..."
}

# View broker logs
function view_broker_logs() {
    clear
    echo "Viewing broker logs..."

    [ ! -d "boundless" ] && echo "Missing boundless directory." && read && return
    cd boundless

    if ! pgrep -f "just broker" > /dev/null; then
        read -p "Broker is not running. Start it? (y/n): " start_choice
        [[ "$start_choice" =~ ^[Yy]$ ]] && echo "Run: cd $(pwd) && just broker" && read
        return
    fi

    echo "Showing logs. Press Ctrl+C to stop."
    just broker logs
    read -p "Press Enter to return..."
}

# Remove node
function remove_node() {
    clear
    echo "Node removal process..."
    echo "WARNING: This will delete all data and the boundless directory."

    read -p "Are you sure? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "Cancelled." && read && return

    [ ! -d "boundless" ] && echo "No boundless directory found." && read && return
    cd boundless
    pgrep -f "just broker" > /dev/null && just broker down

    echo "Cleaning data..."
    just broker clean || echo "Cleanup failed. Proceeding anyway."
    cd ..
    read -p "Final confirmation to delete boundless directory (y/n): " final_confirm
    [[ "$final_confirm" =~ ^[Yy]$ ]] && rm -rf boundless && echo "Directory deleted." || echo "Cancelled."

    read -p "Press Enter to return..."
}

# Multi-GPU setup placeholder
function multi_gpu_setup() {
    clear
    echo "Multi-GPU Setup"

    [ ! -d "boundless" ] && echo "Missing boundless directory." && read && return
    cd boundless

    if ! command -v nvidia-smi &> /dev/null; then
        echo "NVIDIA driver not detected. Install drivers first."
        read && return
    fi

    echo "Available GPUs:"
    nvidia-smi -L
    read -p "Press Enter to return..."
}

# Start main menu
main_menu
