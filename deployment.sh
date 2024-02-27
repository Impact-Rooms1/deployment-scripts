#!/bin/bash

# Check if GITHUB_KEY is set
if [ -z "$GITHUB_KEY" ]; then
    echo "Error: GITHUB_KEY environment variable is not set. Please set it before running this script."
    exit 1
fi

# Function to clone repositories
clone_repo() {
    local repo_url="$1"
    local repo_name="$(basename $repo_url .git)"
    local dest_folder="$2"

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
        npm install
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
            npm run build
        else
            echo "No build command found in package.json for React.js project in $folder"
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
        if ! grep -q "^$value=" "$env_file"; then
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
                pm2 start "$main_script" --update-env --time
            else
                echo "No main script found in package.json for pm2 in $folder"
            fi
        fi
    fi
}

# List of repositories to clone
repositories=("https://$GITHUB_KEY@github.com/example/repo1.git" \
              "https://$GITHUB_KEY@github.com/example/repo2.git")

# Destination folder
destination_folder="$HOME"

# Clone repositories and perform tasks based on project type
for repo in "${repositories[@]}"; do
    clone_repo "$repo" "$destination_folder"
    project_folder="$destination_folder/$(basename "$repo" .git)"
    install_node_deps "$project_folder"
    install_python_deps "$project_folder"

    env_values=($(collect_env_values "$project_folder"))
    check_env_file "$project_folder" "${env_values[@]}"

    build_react_project "$project_folder"

    start_with_pm2 "$project_folder"
done