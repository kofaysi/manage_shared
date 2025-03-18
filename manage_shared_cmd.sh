#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Constants
WORKING_SHARED_ACCOUNT="shared"
SHARED_HOME="/home/$WORKING_SHARED_ACCOUNT"
BOOKMARK_NAME="Shared"
BOOKMARK_PATH="file://$SHARED_HOME"

# Function to add a user
add_user() {
    local user=$1
    local bookmark=${2:-$BOOKMARK_NAME}

    # Add user to group
    gpasswd -a "$user" "$WORKING_SHARED_ACCOUNT"

    # Create symlink in user's home directory
    local user_home="/home/$user"
    ln -sf "$SHARED_HOME" "$user_home/$bookmark"

    # Add bookmark
    local bookmark_file="$user_home/.config/gtk-3.0/bookmarks"
    mkdir -p "$(dirname "$bookmark_file")"
    touch "$bookmark_file"
    echo "$BOOKMARK_PATH" >> "$bookmark_file"
}

# Function to remove a user
remove_user() {
    local user=$1

    # Remove user from group
    gpasswd -d "$user" "$WORKING_SHARED_ACCOUNT"

    # Remove symlink
    local user_home="/home/$user"
    rm -f "$user_home/$BOOKMARK_NAME"

    # Remove bookmark
    local bookmark_file="$user_home/.config/gtk-3.0/bookmarks"
    sed -i "\|$BOOKMARK_PATH|d" "$bookmark_file"
}

# Function to purge the shared directory
purge_shared() {
    userdel "$WORKING_SHARED_ACCOUNT"
    rm -rf "$SHARED_HOME"
}

# Function to list users in the shared group
list_users_in_shared() {
    echo "Listing users in the shared group:"
    getent group "$WORKING_SHARED_ACCOUNT" | awk -F: '{print $4}'
}

# Function to list users not in the shared group
list_users_not_in_shared() {
    echo "Listing users not in the shared group:"
    local all_users=$(getent passwd | awk -F: '{print $1}')
    local shared_users=$(getent group "$WORKING_SHARED_ACCOUNT" | awk -F: '{print $4}' | tr ',' '\n')

    for user in $all_users; do
        if ! grep -qw "$user" <<< "$shared_users"; then
            echo "$user"
        fi
    done
}

# Function to list all shared accounts
list_shared_accounts() {
    echo "Searching for shared accounts with setgid bit set..."
    local -a SHARED_ACCOUNTS
    mapfile -t SHARED_ACCOUNTS < <(find /home -maxdepth 1 -type d -perm -2000 -exec basename {} \;)
    if [ -z "$SHARED_ACCOUNTS" ]; then
        echo "No shared accounts found."
    else
        echo "Shared accounts:"
        echo "$SHARED_ACCOUNTS"
    fi
}

assign_name_to_shared() {
    echo "Assigning a new name to the shared account: $1"
    WORKING_SHARED_ACCOUNT=$1
    # Additional logic to update system configuration or database might be required
}

create_shared_account() {
    echo "Creating shared user and group: $WORKING_SHARED_ACCOUNT"
    sudo useradd -m "$WORKING_SHARED_ACCOUNT"
    sudo groupadd -f "$WORKING_SHARED_ACCOUNT"
    sudo chmod 2770 "/home/$WORKING_SHARED_ACCOUNT"
}

# Parse command line
while [[ "$1" != "" ]]; do
    case "$1" in
        -a | --add)
            if [[ "$2" == "-b" || "$2" == "--bookmark" ]]; then
                add_user "$3" "$4"
                shift 4
            else
                add_user "$2"
                shift 2
            fi
            ;;
        -r | --remove)
            remove_user "$2"
            shift 2
            ;;
        -p | --purge)
            purge_shared
            shift
            ;;
        -u | --users)
            if [[ "$2" == "in" ]]; then
                list_users_in_shared
                shift 2
            elif [[ "$2" == "out" ]]; then
                list_users_not_in_shared
                shift 2
            else
                echo "Invalid list option. Use 'in' or 'out'."
                exit 1
            fi
            ;;
        -s | --shared)
            list_shared_accounts
            shift
            ;;
        -n | --name)
            assign_name_to_shared "$2"
            shift 2
            ;;
        *)
            | [-r|--remove <user>] | [-p|--purge] | [-l|--list in|out] [--shared]"
            echo "Usage: $0 [options] <parameters>"
            echo "Options:"
            echo "  -a, --add <user>          Add a user to the shared group"
            echo "  -b, --bookmark <name>     Name the bookmark in Nautilus"
            echo "  -r, --remove <user>       Remove a user from the shared group"
            echo "  -p, --purge               Purge the shared group"
            echo "  -u, --users in/out        List users in or out of the shared group"
            echo "  -s, --shared              List shared accounts"
            echo "  -n, --name                Assign a new name to the shared account"
            exit 1
            ;;
    esac
done
