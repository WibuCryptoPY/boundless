#!/bin/bash

# Main menu function
function main_menu() {
    while true; do
        clear
        echo "================================================================"
        echo -e "${GREEN}Welcome to WibuCrypto Validator Setup!${NC}"
        echo -e "${BLUE}Join us on Telegram: https://t.me/wibuairdrop142${NC}"
        echo "================================================================"
        echo "Exit script with Ctrl + C"
        echo "Please select an action:"
        echo "1) Install and deploy node"
        echo "2) Check staking balance"
        echo "3) View broker logs"
        echo "4) Remove node"
        echo "5) Multi-GPU version (currently unavailable)"
        echo "q) Exit script"
        echo "================================================================"
        read -p "Enter your choice [1/2/3/4/5/q]: " choice
        case $choice in
            1) install_node ;;
            2) check_stake_balance ;;
            3) view_broker_logs ;;
            4) remove_node ;;
            5) multi_gpu_setup ;;
            q|Q)
                echo "Thank you for using, goodbye!"
                exit 0
                ;;
            *)
                echo "Invalid option, please try again"
                sleep 2
                ;;
        esac
    done
}

# Function to install and deploy node
function install_node() {
    clear
    echo "Starting node installation..."

    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script with sudo"
        exit 1
    fi

    echo "Checking Docker installation..."
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
        echo "Docker installed. Please log out and log back in to apply group changes."
    fi

    echo "Checking NVIDIA Docker support..."
    if ! command -v nvidia-docker &> /dev/null; then
        echo "Installing NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        systemctl restart docker
        echo "NVIDIA Container Toolkit installed"
    fi

    echo "Checking screen installation..."
    if ! command -v screen &> /dev/null; then
        echo "Installing screen..."
        apt-get update
        apt-get install -y screen
        if [ $? -ne 0 ]; then
            echo "Screen installation failed, please install manually"
            exit 1
        fi
        echo "Screen installed"
    fi

    echo "Checking just installation..."
    if ! command -v just &> /dev/null; then
        echo "Installing just..."
        curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
        if [ $? -ne 0 ]; then
            echo "Just installation failed, please install manually"
            exit 1
        fi
        echo "Just installed"
    fi

    echo "Cloning repository..."
    if [ ! -d "boundless" ]; then
        git clone https://github.com/boundless-xyz/boundless
        if [ $? -ne 0 ]; then
            echo "Clone failed, check your network or repository URL"
            exit 1
        fi
    fi

    cd boundless
    echo "Switching to release-0.9 branch..."
    git checkout release-0.9
    if [ $? -ne 0 ]; then
        echo "Failed to switch branch, please check the branch name"
        exit 1
    fi

    echo "Installing Rust and toolchain..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    rustup update
    apt-get install -y cargo

    echo "Installing rzup..."
    curl -L https://risczero.com/install | bash
    source ~/.bashrc
    rzup install rust
    cargo install cargo-risczero
    rzup install cargo-risczero
    rustup update

    echo "Installing bento-client..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc

    echo "Installing boundless-cli..."
    cargo install --locked boundless-cli
    export PATH=$PATH:/root/.cargo/bin
    source ~/.bashrc

    echo "Running setup.sh script..."
    chmod +x ./scripts/setup.sh
    ./scripts/setup.sh

    echo "All dependencies installed!"

    echo "Set your environment variables:"
    echo "Hint: Use Alchemy RPC URL for Ethereum Sepolia testnet"
    read -p "Enter your PRIVATE_KEY: " PRIVATE_KEY
    read -p "Enter your Sepolia RPC_URL: " RPC_URL

    if [[ "$RPC_URL" != *"sepolia"* ]]; then
        echo "Warning: You are not using a Sepolia network RPC URL"
        read -p "Continue using this RPC URL? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Cancelled, please re-run the script"
            exit 1
        fi
    fi

    if [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ]; then
        echo "Error: Both PRIVATE_KEY and RPC_URL must be provided"
        exit 1
    fi

    sed -i '/^PRIVATE_KEY=/d' .env.eth-sepolia 2>/dev/null
    sed -i '/^RPC_URL=/d' .env.eth-sepolia 2>/dev/null

    echo "Writing environment variables to .env.eth-sepolia..."
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> .env.eth-sepolia
    echo "RPC_URL=$RPC_URL" >> .env.eth-sepolia

    if grep -q "PRIVATE_KEY=$PRIVATE_KEY" .env.eth-sepolia && grep -q "RPC_URL=$RPC_URL" .env.eth-sepolia; then
        echo "Environment variables successfully written"
        source .env.eth-sepolia
    else
        echo "Failed to write environment file, check permissions"
        exit 1
    fi

    echo "Run the following to start bento service:"
    echo "cd $(pwd) && just bento"
    read

    echo "Waiting 5 seconds before starting bento_cli..."
    sleep 5
    RUST_LOG=info bento_cli -c 32 | tee /tmp/bento_cli_output.log &
    BENTO_CLI_PID=$!

    echo "Waiting for image_id..."
    while ! grep -q "image_id" /tmp/bento_cli_output.log; do
        sleep 1
    done

    echo "image_id found, test successful!"
    echo "Cleaning up and exiting..."
    kill $BENTO_CLI_PID 2>/dev/null
    rm /tmp/bento_cli_output.log 2>/dev/null
    sleep 3
    exit 0
}

# Check staking balance function
function check_stake_balance() {
    clear
    echo "Check staking balance"
    echo "----------------------------------------"

    if [ ! -f "boundless/.env.eth-sepolia" ]; then
        echo "Error: .env.eth-sepolia file not found"
        read
        return
    fi

    cd boundless
    source .env.eth-sepolia
    if [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ]; then
        echo "Error: Environment variables not loaded properly"
        read
        return
    fi

    read -p "Enter the wallet address to check: " WALLET_ADDRESS
    if [[ ! "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "Invalid Ethereum address format"
        read
        return
    fi

    echo "Querying stake balance..."
    boundless account stake-balance "$WALLET_ADDRESS"
    read
}

# View broker logs function
function view_broker_logs() {
    clear
    echo "View broker logs"
    echo "----------------------------------------"

    if [ ! -d "boundless" ]; then
        echo "Error: boundless directory not found"
        read
        return
    fi

    cd boundless

    if ! pgrep -f "just broker" > /dev/null; then
        echo "Warning: broker service is not running"
        read -p "Start broker service? (y/n): " start_choice
        if [[ "$start_choice" == "y" || "$start_choice" == "Y" ]]; then
            echo "Run: cd $(pwd) && just broker"
            read
        else
            read
            return
        fi
    else
        echo "Broker service is running"
    fi

    read
    just broker logs
    read
}

# Remove node function
function remove_node() {
    clear
    echo "Remove node"
    echo "----------------------------------------"
    echo "Warning: This will completely remove the node"

    read -p "Are you sure you want to delete the node? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        read
        return
    fi

    if [ ! -d "boundless" ]; then
        echo "Error: boundless directory not found"
        read
        return
    fi

    cd boundless

    echo "Stopping broker service..."
    if pgrep -f "just broker" > /dev/null; then
        just broker down
        sleep 2
        echo "Broker stopped"
    fi

    echo "Cleaning node data..."
    just broker clean

    cd ..
    read -p "Final confirmation: Delete boundless directory? (y/n): " final_confirm
    if [[ "$final_confirm" == "y" || "$final_confirm" == "Y" ]]; then
        rm -rf boundless
        echo "Boundless directory deleted"
    else
        echo "Directory deletion cancelled"
    fi

    read
}

# Multi-GPU setup function
function multi_gpu_setup() {
    clear
    echo "Multi-GPU setup"
    echo "----------------------------------------"

    if [ ! -d "boundless" ]; then
        echo "Error: boundless directory not found"
        read
        return
    fi

    cd boundless

    if ! command -v nvidia-smi &> /dev/null; then
        echo "Error: NVIDIA driver not detected"
        read
        return
    fi

    echo "GPU Info:"
    nvidia-smi -L
    read
}

# Start main menu
main_menu
