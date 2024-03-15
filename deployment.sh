#!/bin/bash

# IMPACT ROOMS AUTO DEPLOYMENT SCRIPT

# Check if GITHUB_KEY is set
if [ -z "$GITHUB_KEY" ]; then
    echo "Error: GITHUB_KEY environment variable is not set. Please set it before running this script."
    exit 1
fi

sudo apt update -y
sudo apt install -y jq

# Function to clone repositories
clone_repo() {
    local repo_url="$1"
    local repo_name="$(basename $repo_url .git)"
    local dest_folder="$3"

    if [ -d "$dest_folder/$repo_name" ]; then
        echo "Repository $repo_name already exists in $dest_folder, updating..."
        cd "$dest_folder/$repo_name" || return
        git pull
    else
        echo "Cloning $repo_name into $dest_folder"
        git clone "$repo_url" "$dest_folder/$repo_name"
    fi
}

# Function to install Node.js dependencies
install_node_deps() {
    local folder="$1"
    if [ -f "$folder/package.json" ]; then
        echo "Installing Node.js dependencies in $folder"
        cd "$folder" || return
        npm install -f
    fi
}

# Function to install Python dependencies using Poetry
install_python_deps() {
    local folder="$1"
    if [ -f "$folder/pyproject.toml" ]; then
        echo "Installing Python dependencies in $folder using Poetry"
        cd "$folder" || return
        poetry install
    fi
}

# Function to build React.js projects if a build command exists
build_react_project() {
    local folder="$1"
    if [ -f "$folder/package.json" ]; then
        local build_command=$(jq -r '.scripts.build' "$folder/package.json")
        if [ ! -z "$build_command" ]; then
            echo "Building React.js project in $folder"
            cd "$folder" || return
            export NODE_OPTIONS=--max_old_space_size=4096
            npm run build
        fi
    fi
}

# Function to collect process.env.* values
collect_env_values() {
    local folder="$1"
    local env_values=()

    while IFS= read -r -d '' file; do
        while IFS= read -r line; do
            if [[ $line =~ process\.env\.([A-Za-z0-9_]+) ]]; then
                env_values+=("${BASH_REMATCH[1]}")
            fi
        done < "$file"
    done < <(find "$folder" -type f -name '*.js' -print0)

    echo "${env_values[@]}"
}

# Function to check if values are in .env file
check_env_file() {
    local folder="$1"
    local values=("$@")
    local env_file="$folder/.env"

    if [ ! -f "$env_file" ]; then
        echo "Creating .env file in $folder"
        sudo touch "$env_file"
        sudo chown root:root "$env_file"
        sudo chmod 644 "$env_file"
    fi

    for value in "${values[@]}"; do
        if ! grep -q "^$value\s*=\s*" "$env_file"; then
            echo "$value is missing in .env file"
        fi
    done
}

# Start application with pm2 if no build command is found
start_with_pm2() {
    local folder="$1"
    if [ -f "$folder/package.json" ]; then
        local build_command=$(jq -r '.scripts.build' "$folder/package.json")
        if [ -z "$build_command" ]; then
            local main_script=$(jq -r '.main' "$folder/package.json")
            if [ ! -z "$main_script" ]; then
                echo "Starting application with pm2 in $folder"
                cd "$folder" || return
                
                # run migrations and seeds
                npx sequelize-cli db:migrate
                npx sequelize-cli db:seed:undo:all
                npx sequelize-cli db:seed

                pm2 start "$main_script" --update-env --time
            else
                if [ -f "$folder/startup.sh" ]; then
                    cd "$folder" || return
                    chmod +x startup.sh
                    pm2 start ./startup.sh --update-env --time
                fi
            fi
        fi
    fi
}

# Function to install NVM (Node Version Manager)
install_nvm() {
    if ! command -v nvm &> /dev/null; then
        echo "Installing NVM (Node Version Manager)..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    fi
}

# Function to install Node.js
install_node() {
    if ! nvm list | grep -q "v18.14.0"; then
        echo "Installing Node.js version 18.14.0..."
        nvm install v18.14.0
    fi
}

# Function to install PM2
install_pm2() {
    if ! command -v pm2 &> /dev/null; then
        echo "Installing PM2..."
        npm install -g pm2

        local pm2_startup_output=$(pm2 startup)
        
        if [ $? -eq 0 ]; then
            eval "$pm2_startup_output"
        fi
    fi
}

# Function to install Python version 3.10
install_python() {
    if ! command -v python3.10 &> /dev/null; then
        echo "Installing Python version 3.10..."
        sudo apt update
        sudo apt install -y python3.10
    else
        echo "Python version 3.10 is already installed."
    fi
}

# Function to check if Python command is version 3.10 and install python3-is-python module
check_python_version() {
    local python_version=$(python3 --version 2>&1 | awk '{print $2}')
    if [[ "$python_version" != "3.10"* ]]; then
        echo "Python version is not 3.10, installing python3-is-python module..."
        sudo apt install -y python3-is-python
    else
        echo "Python version is already 3.10."
    fi
}

# Function to install Consul
install_consul() {
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update && sudo apt install consul

    # append some configs to the /etc/consul.d/consul.hcl
    sudo systemctl start consul
}

# Function to check if Consul is installed and running
check_consul() {
    if command -v consul &> /dev/null; then
        if consul members &> /dev/null; then
            echo "Consul is installed and running."
        else
            sudo systemctl start consul
        fi
    else
        install_consul
    fi
}

# List of repositories to clone
repositories=()

# Function to check if a repository URL is provided
check_repo_url() {
    local repo_url="$1"
    if [ -z "$repo_url" ]; then
        echo "Error: Repository URL is required."
        exit 1
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -r|--repository)
        check_repo_url "$2"
        repositories+=("$2")
        shift
        shift
        ;;
        *)
        echo "Unknown option: $key"
        exit 1
        ;;
    esac
done

# Destination folder
destination_folder="$HOME"

# Install necessary tools and dependencies
check_consul
install_nvm
install_node
install_pm2
install_python
check_python_version

# Clone repositories and perform tasks based on project type
for repo_info in "${repositories[@]}"; do
    IFS=':' read -r -a repo_info_array <<< "$repo_info"

    repo="${repo_info_array[0]}"
    version="${repo_info_array[1]}"

    clone_repo "https://$GITHUB_KEY@github.com/Impact-Rooms1/$repo.git" "$version" "$destination_folder"
    project_folder="$destination_folder/$(basename "$repo" .git)"

    env_values=($(collect_env_values "$project_folder"))
    check_env_file "$project_folder" "${env_values[@]}"
    
    install_node_deps "$project_folder"
    install_python_deps "$project_folder"

    build_react_project "$project_folder"

    start_with_pm2 "$project_folder"
done
