#!/bin/bash

# Constants
SHARED_ACCOUNT_DEFAULT="shared"  # Default shared account name

# Check if the script is run with superuser privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Function to check if a USER exists
user_exists() {
    id "$1" &>/dev/null
}

# Function to check if the shared group exists
group_exists() {
    getent group "$1" &>/dev/null
}

# Function to create the shared group
create_shared_group() {
    local group_name=$1
    groupadd "$group_name"
    local group_dir="/home/$group_name"
    mkdir -p "$group_dir"
    chmod 2770 "$group_dir"
    echo "Created group '$group_name' with home directory '$group_dir'."
}

# Function to prompt for group creation
prompt_for_group_creation() {
    echo "Shared group '$SHARED_ACCOUNT' does not exist."
    read -p "Would you like to create it? (y/n): " response
    if [[ "$response" == "y" ]]; then
        read -p "Enter a name for the shared group (default $SHARED_ACCOUNT_DEFAULT): " new_name
        SHARED_ACCOUNT=${new_name:-$SHARED_ACCOUNT}
        create_shared_group "$SHARED_ACCOUNT"
    else
        echo "Operation cancelled."
        exit 1
    fi
}

# Function to add a USER to the shared group
add_user_to_shared() {
    local USER=$1

    if ! user_exists "$USER"; then
        echo "User '$USER' does not exist."
        return 1
    fi

    if ! group_exists "$SHARED_ACCOUNT"; then
        prompt_for_group_creation
    fi


    # Add USER to group
    usermod -aG "$SHARED_ACCOUNT" "$USER"

    create_link_in_USER_HOME
    create_bookmark_in_Nautilus
}

create_link_in_USER_HOME() {
    # Create symlink in USER's home directory
    local USER_HOME="/home/$USER"
    ln -sf "$SHARED_HOME" "$USER_HOME/$SHARED_ACCOUNT"

}

create_bookmark_in_Nautilus() {
    # Add bookmark
    local bookmark=$BOOKMARK_NAME
    local bookmark_file="$USER_HOME/.config/gtk-3.0/bookmarks"
    mkdir -p "$(dirname "$bookmark_file")"
    touch "$bookmark_file"
    echo "$BOOKMARK_PATH" >> "$bookmark_file"
    echo "Linked '/home/$SHARED_ACCOUNT' to '$bookmark_file' and added bookmark."
}

# Function to handle the creation of links and bookmarks
setup_user_environment() {
    local USER=$1
    local SHARED_ACCOUNT=${2:-"Shared"}
    local USER_HOME="/home/$USER"
    local SHARED_HOME="/home/$SHARED_ACCOUNT"
    local BOOKMARK_NAME
}

# Function to remove a USER
remove_user_from_shared() {
    local USER=$1

    # Remove USER from group
    echo "Removing $USER from group, deleting symlink, and removing bookmark."
    gpasswd -d "$USER" "$SHARED_ACCOUNT"

    remove_bookmark_from_user
    remove_link_to_shared_from_user
}

remove_link_to_shared_from_user() {
  SHARED_LINK=$(find "$USER_HOME" -maxdepth 1 -type l -lname "/home/$SHARED_ACCOUNT" 2>/dev/null)
  rm -f "$SHARED_LINK"
}
remove_bookmark_from_user() {
    # Remove bookmark
    sed -i "\|$BOOKMARK|d" "$BOOKMARKS_FILE"
}

# Function to purge the shared directory
purge_shared() {
    userdel "$SHARED_ACCOUNT"
    rm -rf "$SHARED_HOME"
}

list_user() {
  echo "Fetching system users excluding the shared account..."
  USERS=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | grep -v "^$SHARED_ACCOUNT$")
  echo "$USERS"
}
# Function to list users in the shared group
list_users_in_shared() {
    echo "Listing users in the shared group:"
    getent group "$SHARED_ACCOUNT" | awk -F: '{print $4}'
    # GROUP_USERS=$(getent group "$SHARED_ACCOUNT" | cut -d: -f4 | tr ',' ' ')
}

# Function to list users not in the shared group
list_users_not_in_shared() {
    echo "Listing users not in the shared group:"
    local all_users=$(getent passwd | awk -F: '{print $1}')
    local shared_users=$(getent group "$SHARED_ACCOUNT" | awk -F: '{print $4}' | tr ',' '\n')

    for USER in $all_users; do
        if ! grep -qw "$USER" <<< "$shared_users"; then
            echo "$USER"
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

create_shared_account() {
    echo "Creating shared USER and group: $SHARED_ACCOUNT"
    sudo useradd -m "$SHARED_ACCOUNT"
    sudo groupadd -f "$SHARED_ACCOUNT"
    sudo chmod 2770 "/home/$SHARED_ACCOUNT"
}

# Parse command line
while [[ "$1" != "" ]]; do
    case "$1" in
        -a | --add)
            param_user_to_add_to_shared="$2"
            shift 2
            ;;
        --add-all)
            param_all_users_to_shared=TRUE
            shift 1
            ;;
        -b | --bookmark)
            BOOKMARK_NAME=${2:-$SHARED_ACCOUNT}
            shift 2
            ;;
        -r | --remove)
            param_user_to_remove_from_shared="$2"
            shift 2
            ;;
        -p | --purge | --remove-all)
            purge_shared
            param_all_users_from_shared=TRUE
            # no shifting needed here, we're done.
            exit 0
            ;;
        -u | --users)
            if [[ "$2" == "in"* ]]; then
                param_list_users_in_shared="TRUE"
                shift 2
            elif [[ "$2" == "ex"* ]]; then
                param_list_users_not_in_shared="TRUE"
                shift 2
            else
                echo "Invalid list option. Use 'in[cluded]' or 'ex[cluded]'."
                exit 1
            fi
            ;;
        -s | --shared)
            param_list_shared_accounts="TRUE"
            shift
            ;;
        -n | --name)
            param_name_shared="$2"
            shift 2
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            echo "Usage: $0 [options] <parameters>"
            echo "Options:"
            echo "  -a, --add <USER>          Add a USER to the shared group"
            echo "  -b, --bookmark <name>     Name the bookmark in Nautilus"
            echo "  -r, --remove <USER>       Remove a USER from the shared group"
            echo "  -p, --purge               Purge the shared group"
            echo "  -u, --users in/out        List users in or out of the shared group"
            echo "  -s, --shared              List shared accounts"
            echo "  -n, --name                Assign a new name to the shared account"
            exit 1
            ;;
    esac
done

if [[ -z $param_name_shared ]];
  setup_user_environment "$param_name_shared"
then
  setup_user_environment $SHARED_ACCOUNT_DEFAULT
fi
