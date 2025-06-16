#!/bin/bash

function main_menu() {
    while true; do
        clear
        echo "================================================================"
		echo "Welcome to WibuCrypto Validator Setup!"
		echo "Join us on Telegram: https://t.me/wibuairdrop142$"
        echo "================================================================"
		echo "To exit the script, press Ctrl + C"
		echo "Please select the operation to be performed:"
		echo "1) Install and deploy nodes"
		echo "2) View the pledge balance"
		echo "3) View the broker log"
		echo "4) Delete nodes"
		echo "q) Exit the script"
        echo "================================================================"
		read -p "Please enter options [1/2/3/4/q]: " choice
        case $choice in
            1)
                install_node
                ;;
            2)
                check_stake_balance
                ;;
            3)
                view_broker_logs
                ;;
            4)
                remove_node
                ;;
            q|Q)
                echo "Thanks for using, bye!"
                exit 0
                ;;
            *)
                echo "Invalid option, please select again"
                sleep 2
                ;;
        esac
    done
}

function install_node() {
    clear
    echo "Start installing and deploying nodes..."
    
    if [ "$EUID" -ne 0 ]; then 
        echo "Please run this script with sudo"
        exit 1
    fi

    echo "Checking Docker installation status..."
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
        echo "Docker installation is complete, please log out and log back in for group membership to take effect"
    fi

    echo "Check NVIDIA Docker support..."
    if ! command -v nvidia-docker &> /dev/null; then
        echo "正在安装 NVIDIA Container Toolkit..."
        distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
        curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | apt-key add -
        curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | tee /etc/apt/sources.list.d/nvidia-docker.list
        apt-get update
        apt-get install -y nvidia-container-toolkit
        systemctl restart docker
        echo "NVIDIA Container Toolkit Installation Complete"
    fi

    echo "Checking screen installation status..."
    if ! command -v screen &> /dev/null; then
        echo "Installing screen..."
        apt-get update
        apt-get install -y screen
        if [ $? -ne 0 ]; then
            echo "Screen installation failed, please install manually"
            exit 1
        fi
        echo "Screen installation complete"
    fi

    echo "Checking just installation status..."
    if ! command -v just &> /dev/null; then
        echo "Installing just..."
        curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh | bash -s -- --to /usr/local/bin
        if [ $? -ne 0 ]; then
            echo "just installation failed, please install manually"
            exit 1
        fi
        echo "just Installation completed"
    fi

    echo "Starting cloning repository..."
    if [ ! -d "boundless" ]; then
        git clone https://github.com/boundless-xyz/boundless
        if [ $? -ne 0 ]; then
            echo "Cloning failed, please check whether the network connection or warehouse address is correct"
            exit 1
        fi
    fi

    cd boundless
    echo "Switching to release-0.10 branch..."
    git checkout release-0.10
    if [ $? -ne 0 ]; then
        echo "Failed to switch branches. Please check whether the branch name is correct."
        exit 1
    fi

    echo "Install Rust and related toolchains..."
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
    if [ $? -ne 0 ]; then
        echo "rustup installation failed, please check network connection or install manually"
        exit 1
    fi
    echo "Rustup installation completed"

    echo "Updating rustup..."
    rustup update
    if [ $? -ne 0 ]; then
        echo "rustup update failed, please check network connection or update manually"
        exit 1
    fi
    echo "rustup update completed"

    echo "Installing Rust toolchain..."
    apt-get update
    apt-get install -y cargo
    if [ $? -ne 0 ]; then
        echo "Rust toolchain installation failed, please install manually"
        exit 1
    fi
    echo "Rust toolchain installed"

    echo "Verifying Cargo installation..."
    cargo --version
    if [ $? -ne 0 ]; then
        echo "Cargo verification failed, please check your installation"
        exit 1
    fi
    echo "Cargo verification passed"

    echo "Installing rzup..."
	curl -L https://risczero.com/install | bash

	# Add rzup path to environment
	export PATH="$HOME/.cargo/bin:$PATH"
	echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
	source ~/.bashrc
    if [ $? -ne 0 ]; then
        echo "rzup installation failed, please check the network connection or install manually"
        exit 1
    fi
    echo "rzup installation complete"

	echo "Verifying rzup installation..."
	if [ -f "$HOME/.cargo/bin/rzup" ]; then
		"$HOME/.cargo/bin/rzup" --version
	else
		echo "rzup not found at expected path: $HOME/.cargo/bin/rzup"
		exit 1
	fi
    echo "rzup verification passed"

    echo "Installing RISC Zero Rust toolchain..."
    "$HOME/.risc0/bin/rzup" install rust
    if [ $? -ne 0 ]; then
        echo "RISC Zero Rust toolchain installation failed, please install manually"
        exit 1
    fi
    echo "RISC Zero Rust toolchain installation completed"

    echo "Installing cargo-risczero..."
    cargo install cargo-risczero
    "$HOME/.risc0/bin/rzup" install cargo-risczero
    if [ $? -ne 0 ]; then
        echo "cargo-risczero installation failed, please check network connection or install manually"
        exit 1
    fi
    echo "cargo-risczero installation completed"

    echo "Update rustup again..."
    rustup update
    if [ $? -ne 0 ]; then
        echo "rustup Update failed, please check the network connection or update manually"
        exit 1
    fi
    echo "rustup update completed"

    echo "Installing bento-client..."
    cargo install --git https://github.com/risc0/risc0 bento-client --bin bento_cli
    echo 'export PATH="$HOME/.cargo/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    if [ $? -ne 0 ]; then
        echo "bento-client installation failed, please check the network connection or install manually"
        exit 1
    fi
    echo "bento-client installation completed"

    echo "Verifying bento-client installation..."
    bento_cli --version
    if [ $? -ne 0 ]; then
        echo "bento-client verification failed, please check the installation"
        exit 1
    fi
    echo "bento-client verification passed"

    echo "Installing boundless-cli..."
    cargo install --locked boundless-cli
    export PATH=$PATH:/root/.cargo/bin
    source ~/.bashrc
    if [ $? -ne 0 ]; then
        echo "boundless-cli installation failed, please check the network connection or install manually"
        exit 1
    fi
    echo "boundless-cli installation completed"

    echo "Verifying boundless-cli installation..."
    boundless -h
    if [ $? -ne 0 ]; then
        echo "boundless-cli verification failed, please check the installation"
        exit 1
    fi
    echo "boundless-cli verification passed"

    echo "Execute the setup.sh script..."
    chmod +x ./scripts/setup.sh
    ./scripts/setup.sh
    if [ $? -ne 0 ]; then
        echo "Failed to execute setup.sh. Please check the script permissions or execute it manually."
        exit 1
    fi

    echo "All dependencies installed!"
    echo "Please log out and log back in for the Docker group membership to take effect"

    echo "Please set your environment variables:"
    echo "Please use the Alchemy RPC URL of the Ethereum Sepolia testnet"
    echo "Format: https://eth-sepolia.g.alchemy.com/v2/YOUR-API-KEY"
    echo "----------------------------------------"

    read -p "Please enter your PRIVATE_KEY: " PRIVATE_KEY
    read -p "Please enter your Sepolia RPC_URL: " RPC_URL

    if [[ "$RPC_URL" != *"sepolia"* ]]; then
        echo "Warning: You are not using the RPC URL of the Sepolia network, this may cause connection issues"
        read -p "Do you want to continue using the current RPC URL? (y/n): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Unset, please rerun the script"
            exit 1
        fi
    fi

    if [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ]; then
        echo "Error: Please enter a valid PRIVATE_KEY and RPC_URL"
        exit 1
    fi

    sed -i '/^PRIVATE_KEY=/d' .env.eth-sepolia 2>/dev/null
    sed -i '/^RPC_URL=/d' .env.eth-sepolia 2>/dev/null

    echo "Writing environment variables to .env.eth-sepolia..."
    echo "PRIVATE_KEY=$PRIVATE_KEY" >> .env.eth-sepolia
    echo "RPC_URL=$RPC_URL" >> .env.eth-sepolia

    if grep -q "PRIVATE_KEY=$PRIVATE_KEY" .env.eth-sepolia && grep -q "RPC_URL=$RPC_URL" .env.eth-sepolia; then
        echo "The environment variables have been successfully written to the .env.eth-sepolia file!"
        echo "Loading environment variables..."
        source .env.eth-sepolia
        if [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ]; then
            echo "Error: Failed to load .env.eth-sepolia file, please check the file contents"
            exit 1
        fi
        echo "Environment variables loaded successfully!"
    else
        echo "Error: Failed to write .env.eth-sepolia file, please check file permissions"
        exit 1
    fi

    echo "Run the following command in a new terminal to start the bento service:"
    echo "cd $(pwd) && just bento"
    echo "When finished, press Enter to continue..."
    read

    echo "Waiting 5 seconds before launching bento_cli..."
    sleep 5

    echo "Starting bento_cli..."
    RUST_LOG=info bento_cli -c 32 | tee /tmp/bento_cli_output.log &
    BENTO_CLI_PID=$!

    echo "Waiting for image_id to be displayed..."
    while ! grep -q "image_id" /tmp/bento_cli_output.log; do
        sleep 1
    done

    echo "image_id is displayed, the test is successful!"
    echo "Cleaning up and exiting..."
    kill $BENTO_CLI_PID 2>/dev/null
    rm /tmp/bento_cli_output.log 2>/dev/null
    sleep 3
    exit 0

    echo "Setting up testnet environment..."
    source <(just env testnet)
    if [ $? -ne 0 ]; then
        echo "Failed to set up the testnet environment. Please check the network connection or set it up manually."
        exit 1
    fi
    echo "The testnet environment is set up!"

    echo "----------------------------------------"
	echo "Please set the deposit amount (USDC):"
	echo "Note: Please make sure there is enough USDC in your account"
    echo "----------------------------------------"

    while true; do
        read -p "Please enter the amount of USDC to deposit:" USDC_AMOUNT
        if [[ "$USDC_AMOUNT" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            break
        else
            echo "Error: Please enter a valid number"
        fi
    done

    echo "Deposit operation in progress..."
    echo "Deposit amount: $USDC_AMOUNT USDC"
    boundless account deposit-stake "$USDC_AMOUNT"

    if [ $? -ne 0 ]; then
		echo "Deposit operation failed, please check:"
		echo "1. Is the account balance sufficient?"
		echo "2. Is the network connection normal?"
		echo "3. Are the environment variables set correctly?"
        exit 1
    fi

    echo "Deposit operation completed!"

	echo "Please run the following command in a new terminal to start the broker service:"
	echo "cd $(pwd) && just broker"
	echo "When finished, press Enter to continue..."
    read

	echo "Script execution completed!"

	echo "Press Enter to return to the main menu..."
    read
}

function check_stake_balance() {
    clear
	echo "Check the pledge balance"
    echo "----------------------------------------"
    
    if [ ! -f "boundless/.env.eth-sepolia" ]; then
		echo "Error: .env.eth-sepolia file not found"
		echo "Please run option 1 to complete the installation and deployment"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

    cd boundless
    source .env.eth-sepolia
    if [ -z "$PRIVATE_KEY" ] || [ -z "$RPC_URL" ]; then
		echo "Error: Environment variables not loaded correctly"
		echo "Please check the contents of the .env.eth-sepolia file"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

    read -p "Please enter the wallet address to be queried:" WALLET_ADDRESS
    
    if [[ ! "$WALLET_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
		echo "Error: Invalid wallet address format"
		echo "Please make sure you entered a valid Ethereum address"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

	echo "Querying the pledge balance..."
	echo "Wallet address: $WALLET_ADDRESS"
    echo "----------------------------------------"
    
    boundless account stake-balance "$WALLET_ADDRESS"
    
    if [ $? -ne 0 ]; then
		echo "Query failed, please check:"
		echo "1. Is the wallet address correct?"
		echo "2. Is the network connection normal?"
		echo "3. Are the environment variables set correctly?"
    fi
    
    echo "----------------------------------------"
	echo "Press Enter to return to the main menu..."
    read
}

function view_broker_logs() {
    clear
    echo "View broker logs"
    echo "----------------------------------------"
    
    if [ ! -d "boundless" ]; then
		echo "Error: boundless directory not found"
		echo "Please run option 1 to complete the installation and deployment"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

    cd boundless

    if ! pgrep -f "just broker" > /dev/null; then
		echo "Warning: broker service is not running"
		echo "Do you want to start the broker service? (y/n)"
		read -p "Please enter options [y/n]: " start_choice
        if [[ "$start_choice" == "y" || "$start_choice" == "Y" ]]; then
			echo "Please run the following command in a new terminal to start the broker service:"
			echo "cd $(pwd) && just broker"
			echo "When finished, press Enter to continue..."
            read
        else
			echo "Press Enter to return to the main menu..."
            read
            return
        fi
    else
        echo "The broker service is already running"
    fi

    echo "----------------------------------------"
	echo "Log viewing instructions:"
	echo "1. The broker service is already running in the background"
	echo "2. Use Ctrl+C to stop viewing the log (the service will continue to run in the background)"
	echo "----------------------------------------"
	echo "Press Enter to start viewing the log..."
    read

    just broker logs

    echo "----------------------------------------"
	echo "Log viewing has ended"
	echo "Broker service is still running in the background"
	echo "Press Enter to return to the main menu..."
    read
}

function remove_node() {
    clear
	echo "Delete node"
	echo "----------------------------------------"
	echo "Warning: This operation will completely delete the node, including:"
	echo "1. Stop broker service"
	echo "2. Clean up all node data"
	echo "3. Delete the entire boundless directory"
    echo "----------------------------------------"
    
    read -p "Are you sure you want to delete the node? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
		echo "Delete operation canceled"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

    if [ ! -d "boundless" ]; then
		echo "Error: boundless directory not found"
		echo "Press Enter to return to the main menu..."
        read
        return
    fi

    cd boundless

    echo "Stopping broker service..."
    if pgrep -f "just broker" > /dev/null; then
        just broker down
        sleep 2
        echo "The broker service has stopped"
    else
        echo "The broker service is not running"
    fi

    echo "Cleaning up node data..."
    just broker clean
    if [ $? -ne 0 ]; then
        echo "WARNING: An error occurred while cleaning data, but directory deletion will continue"
    else
        echo "Node data has been cleaned"
    fi

    cd ..

    echo "Removing boundless directory..."
    read -p "Final confirmation: Do you want to delete the entire boundless directory? (y/n): " final_confirm
    if [[ "$final_confirm" == "y" || "$final_confirm" == "Y" ]]; then
        rm -rf boundless
        if [ $? -eq 0 ]; then
            echo "The boundless directory has been deleted"
        else
            echo "Error: Failed to delete directory, please delete manually"
        fi
    else
        echo "Directory Undeleted"
    fi

    echo "----------------------------------------"
	echo "Node deletion completed"
	echo "Press Enter to return to the main menu..."
    read
}

main_menu
