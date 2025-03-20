#!/bin/bash

# Date: 2025-02-04
# Author: https://github.com/kofaysi
# Description: This script manages the shared account and the users assigned to the shared group interactively, including bookmark management.
# Inspiration: https://forum.zorin.com/t/how-to-transfer-files-from-one-user-to-another/
# Changelog:
# - 2025-03-16 Remove all sudo and pkexec commands. The file has to be run by sudo or pkexec

# Identify shared account by finding home directories with setgid bit (+s) set
echo "Searching for shared accounts with setgid bit set..."
SHARED_ACCOUNTS=$(pkexec find /home -maxdepth 1 -type d -perm -2000 -exec basename {} \;)

if [[ -z "$SHARED_ACCOUNTS" ]]; then
    echo "No shared account found. Prompting user for creation."
    SHARED_ACCOUNT=$(zenity --entry --title="Create Shared Account" --text="No shared account has been found. Enter the name for the shared account:" --entry-text="Shared")
    SHARED_ACCOUNT=${SHARED_ACCOUNT:-Shared}
    echo "Creating shared user and group: $SHARED_ACCOUNT"
    pkexec sh -c 'useradd -m "$1" && \
                  groupadd -f "$1" && \
                  chmod 2770 "/home/$1"' sh "$SHARED_ACCOUNT"
elif [[ $(echo "$SHARED_ACCOUNTS" | wc -w) -eq 1 ]]; then
    SHARED_ACCOUNT="$SHARED_ACCOUNTS"
    echo "Only one shared account found: $SHARED_ACCOUNT. Proceeding with management."
else
    echo "Multiple shared accounts found. Prompting user for selection."
    SHARED_ACCOUNT=$(zenity --list --title="Manage Shared Account" --text="Select the shared account to manage:" --column="Shared Account" $SHARED_ACCOUNTS)
    if [[ -z "$SHARED_ACCOUNT" ]]; then
        zenity --warning --title="No Selection" --text="No shared account selected. Exiting."
        exit 1
    fi
fi

echo "Fetching system users excluding the shared account..."
USERS=$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | grep -v "^$SHARED_ACCOUNT$")
echo "System users: $USERS"

echo "Fetching users in shared group..."
GROUP_USERS=$(getent group "$SHARED_ACCOUNT" | cut -d: -f4 | tr ',' ' ')
echo "Users in shared group: $GROUP_USERS"

CHECKLIST=""
for USER in $USERS; do
    if [[ " $GROUP_USERS " =~ " $USER " ]]; then
        CHECKLIST+="TRUE $USER "
    else
        CHECKLIST+="FALSE $USER "
    fi
done

SELECTED_USERS=$(zenity --list --title="Modify Group Content" --text="Add or remove users in the \'$SHARED_ACCOUNT\' group:" \
    --checklist --column="Select" --column="User" $CHECKLIST --separator=" ")

for USER in $USERS; do
    USER_HOME="/home/$USER"
    BOOKMARK="file://$USER_HOME/Shared"
    BOOKMARKS_DIR="$USER_HOME/.config/gtk-3.0"
    BOOKMARKS_FILE="$BOOKMARKS_DIR/bookmarks"

    if [[ " $SELECTED_USERS " =~ " $USER " ]]; then
        if [[ " $GROUP_USERS " =~ " $USER " ]]; then
            echo "$USER is already in the group, skipping modification."
        elif [ "$USER_HOME" != "/home/$SHARED_ACCOUNT" ]; then
            # Avoid creating a link in the shared directory to itself
            echo "Adding $USER to group, creating symlink, and adding bookmark."
            pkexec sh -c 'usermod -aG "$1" "$2" && \
                          mkdir -p "$3/.config/gtk-3.0" && \
                          touch "$3/.config/gtk-3.0/bookmarks" && \
                          ln -sf "/home/$1" "$3/Shared" && \
                          echo "$4" >> "$3/.config/gtk-3.0/bookmarks"' sh "$SHARED_ACCOUNT" "$USER" "$USER_HOME" "$BOOKMARK"
        fi
    else
        if [[ " $GROUP_USERS " =~ " $USER " ]]; then
            echo "Removing $USER from group, deleting symlink, and removing bookmark."
            SHARED_LINK=$(find "$USER_HOME" -maxdepth 1 -type l -lname "/home/$SHARED_ACCOUNT" 2>/dev/null)
            pkexec sh -c 'gpasswd -d "$1" "$2" && \
                          rm -f "$3" && \
                          sed -i "\|$4|d" "$5"' sh "$USER" "$SHARED_ACCOUNT" "$SHARED_LINK" "$BOOKMARK" "$BOOKMARKS_FILE"
        else
            echo "$USER was not in the shared group, skipping modification."
        fi
    fi
done

echo "Checking if any users remain in the shared group..."
REMAINING_USERS=$(getent group "$SHARED_ACCOUNT" | cut -d: -f4)
if [[ -z "$REMAINING_USERS" ]]; then
    zenity --question --title="Remove Shared Account" --text="No users remain in the shared group. Remove shared account and its home?"
    if [[ $? -eq 0 ]]; then
        echo "Removing shared user, home directory, and group."
        pkexec sh -c 'userdel "$1" && rm -rf "/home/$1"' sh "$SHARED_ACCOUNT"
        if getent group "$SHARED_ACCOUNT" >/dev/null; then
            echo "Removing group: $SHARED_ACCOUNT"
            pkexec groupdel "$SHARED_ACCOUNT"
        else
            echo "Group $SHARED_ACCOUNT does not exist, skipping removal."
        fi
        zenity --info --title="Cleanup Complete" --text="Shared account and its home have been removed."
    fi
fi