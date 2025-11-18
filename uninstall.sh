#!/bin/bash

# uninstall.sh - Uninstall utilities from flatpak, snap, and apt
# Usage: ./uninstall.sh [-e|--exact] <utility-name>

set -euo pipefail

EXACT_MATCH=false
SEARCH_TERM=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--exact)
            EXACT_MATCH=true
            shift
            ;;
        *)
            if [ -z "$SEARCH_TERM" ]; then
                SEARCH_TERM="$1"
            else
                echo "Error: Multiple search terms provided"
                exit 1
            fi
            shift
            ;;
    esac
done

if [ -z "$SEARCH_TERM" ]; then
    echo "Usage: $0 [-e|--exact] <utility-name>"
    echo "  -e, --exact    Match exact package name only (no partial matches)"
    echo ""
    echo "Examples:"
    echo "  $0 firefox              # Search for packages containing 'firefox'"
    echo "  $0 -e firefox          # Search for packages exactly named 'firefox'"
    echo "  $0 --exact io.github.lainsce.Khronos  # Exact match for flatpak app"
    exit 1
fi

FOUND_PACKAGES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ "$EXACT_MATCH" = true ]; then
    echo -e "${BLUE}Searching for exact match '${SEARCH_TERM}' in package managers...${NC}\n"
else
    echo -e "${BLUE}Searching for '${SEARCH_TERM}' in package managers...${NC}\n"
fi

# Search in Flatpak
echo -e "${YELLOW}=== Flatpak Packages ===${NC}"
FLATPAK_RESULTS=$(flatpak search "$SEARCH_TERM" 2>/dev/null || true)
if [ -n "$FLATPAK_RESULTS" ] && [ "$FLATPAK_RESULTS" != "No matches found" ]; then
    echo "$FLATPAK_RESULTS"
    # Extract package names - flatpak search outputs tab-separated: Name, Description, Application ID, Version, Branch, Remote
    # Application ID is in the 3rd column (tab-separated)
    while IFS=$'\t' read -r name description app_id version branch remote; do
        # Skip empty lines
        if [ -z "$app_id" ]; then
            continue
        fi
        # Application ID format: org.example.App (at least 3 dot-separated segments)
        if [[ "$app_id" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z0-9][a-zA-Z0-9.-]* ]]; then
            # In exact match mode, only include if app_id or name exactly matches
            if [ "$EXACT_MATCH" = true ]; then
                if [ "$app_id" = "$SEARCH_TERM" ] || [ "$name" = "$SEARCH_TERM" ]; then
                    FOUND_PACKAGES+=("flatpak:$app_id")
                fi
            else
                FOUND_PACKAGES+=("flatpak:$app_id")
            fi
        fi
    done <<< "$FLATPAK_RESULTS"
else
    echo "No matches found"
fi

echo ""

# Search in Snap
echo -e "${YELLOW}=== Snap Packages ===${NC}"
SNAP_RESULTS=$(snap find "$SEARCH_TERM" 2>/dev/null || true)
if [ -n "$SNAP_RESULTS" ] && [ "$SNAP_RESULTS" != "No matching snaps found" ]; then
    echo "$SNAP_RESULTS"
    # Extract package names - snap find outputs: Name, Version, Publisher, Notes
    # Skip header line and extract first column (Name)
    while IFS= read -r line; do
        # Skip header line
        if [[ "$line" =~ ^Name[[:space:]]+Version ]] || [[ "$line" =~ ^[-=]+ ]]; then
            continue
        fi
        # Extract snap name (first field)
        if [[ $line =~ ^[[:space:]]*([a-zA-Z0-9][a-zA-Z0-9-]*) ]]; then
            SNAP_NAME="${BASH_REMATCH[1]}"
            if [ -n "$SNAP_NAME" ] && [ "$SNAP_NAME" != "Name" ]; then
                # In exact match mode, only include if snap name exactly matches
                if [ "$EXACT_MATCH" = true ]; then
                    if [ "$SNAP_NAME" = "$SEARCH_TERM" ]; then
                        FOUND_PACKAGES+=("snap:$SNAP_NAME")
                    fi
                else
                    FOUND_PACKAGES+=("snap:$SNAP_NAME")
                fi
            fi
        fi
    done <<< "$SNAP_RESULTS"
else
    echo "No matches found"
fi

echo ""

# Search in APT
echo -e "${YELLOW}=== APT Packages ===${NC}"
# Update package list if needed (non-interactive)
if ! apt-cache search "$SEARCH_TERM" &>/dev/null; then
    echo "Updating package cache..."
    sudo apt update -qq 2>/dev/null || true
fi

APT_RESULTS=$(apt-cache search "$SEARCH_TERM" 2>/dev/null || true)
if [ -n "$APT_RESULTS" ]; then
    echo "$APT_RESULTS" | head -20  # Limit to first 20 results
    APT_LINE_COUNT=$(echo "$APT_RESULTS" | wc -l)
    if [ "$APT_LINE_COUNT" -gt 20 ]; then
        echo "... (showing first 20 results, total: $APT_LINE_COUNT)"
    fi
    # Extract package names - apt-cache search outputs: package-name - description
    while IFS= read -r line; do
        # Extract package name (first field before space or dash)
        if [[ $line =~ ^([a-zA-Z0-9][a-zA-Z0-9.+-]*) ]]; then
            PKG_NAME="${BASH_REMATCH[1]}"
            if [ -n "$PKG_NAME" ]; then
                # In exact match mode, only include if package name exactly matches
                if [ "$EXACT_MATCH" = true ]; then
                    if [ "$PKG_NAME" = "$SEARCH_TERM" ]; then
                        FOUND_PACKAGES+=("apt:$PKG_NAME")
                    fi
                else
                    FOUND_PACKAGES+=("apt:$PKG_NAME")
                fi
            fi
        fi
    done <<< "$APT_RESULTS"
else
    echo "No matches found"
fi

echo ""

# If no packages found, exit
if [ ${#FOUND_PACKAGES[@]} -eq 0 ]; then
    echo -e "${RED}No packages found matching '${SEARCH_TERM}'${NC}"
    exit 0
fi

# Display found packages
echo -e "${GREEN}Found ${#FOUND_PACKAGES[@]} package(s):${NC}"
for i in "${!FOUND_PACKAGES[@]}"; do
    echo "  $((i+1)). ${FOUND_PACKAGES[$i]}"
done

echo ""
read -p "Do you want to uninstall these packages? (yes/no): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Uninstall packages
for package in "${FOUND_PACKAGES[@]}"; do
    if [[ $package =~ ^flatpak:(.+)$ ]]; then
        APP_ID="${BASH_REMATCH[1]}"
        echo -e "${BLUE}Uninstalling flatpak package: ${APP_ID}${NC}"
        flatpak uninstall --delete-data -y "$APP_ID" 2>/dev/null || {
            echo -e "${RED}Failed to uninstall flatpak package: ${APP_ID}${NC}"
        }
    elif [[ $package =~ ^snap:(.+)$ ]]; then
        SNAP_NAME="${BASH_REMATCH[1]}"
        echo -e "${BLUE}Uninstalling snap package: ${SNAP_NAME}${NC}"
        sudo snap remove "$SNAP_NAME" 2>/dev/null || {
            echo -e "${RED}Failed to uninstall snap package: ${SNAP_NAME}${NC}"
        }
    elif [[ $package =~ ^apt:(.+)$ ]]; then
        PKG_NAME="${BASH_REMATCH[1]}"
        echo -e "${BLUE}Uninstalling apt package: ${PKG_NAME}${NC}"
        
        # Check if package is installed before proceeding
        if ! dpkg -l "$PKG_NAME" &>/dev/null; then
            echo -e "${YELLOW}  Package ${PKG_NAME} is not installed, skipping...${NC}"
            continue
        fi
        
        # Get all files associated with the package before removal
        PKG_FILES=$(dpkg -L "$PKG_NAME" 2>/dev/null || true)
        
        # Extract package name without version for desktop file matching
        PKG_BASE_NAME=$(echo "$PKG_NAME" | cut -d':' -f1 | cut -d'+' -f1)
        
        # Remove the package and purge configuration files
        sudo apt-get remove --purge -y "$PKG_NAME" 2>/dev/null || {
            echo -e "${RED}Failed to uninstall apt package: ${PKG_NAME}${NC}"
            continue
        }
        
        # Remove desktop files from common locations
        echo -e "${BLUE}  Removing desktop files and associated data...${NC}"
        
        # Remove desktop files from system and user directories
        # Use find to safely handle cases where files don't exist
        for desktop_dir in /usr/share/applications /usr/local/share/applications "${HOME}/.local/share/applications"; do
            if [ -d "$desktop_dir" ]; then
                # Find and remove desktop files matching package name
                find "$desktop_dir" -maxdepth 1 -type f -name "*${PKG_BASE_NAME}*.desktop" -exec sudo rm -f {} \; 2>/dev/null || \
                find "$desktop_dir" -maxdepth 1 -type f -name "*${PKG_BASE_NAME}*.desktop" -exec rm -f {} \; 2>/dev/null || true
                find "$desktop_dir" -maxdepth 1 -type f -name "*${PKG_NAME}*.desktop" -exec sudo rm -f {} \; 2>/dev/null || \
                find "$desktop_dir" -maxdepth 1 -type f -name "*${PKG_NAME}*.desktop" -exec rm -f {} \; 2>/dev/null || true
            fi
        done
        
        # Remove from package files list if available
        if [ -n "$PKG_FILES" ]; then
            while IFS= read -r file; do
                # Remove desktop files
                if [[ "$file" =~ \.desktop$ ]] && [ -f "$file" ]; then
                    sudo rm -f "$file" 2>/dev/null || true
                fi
                # Remove configuration directories
                if [[ "$file" =~ ^/etc/ ]] && [ -d "$file" ]; then
                    sudo rm -rf "$file" 2>/dev/null || true
                fi
            done <<< "$PKG_FILES"
        fi
        
        # Remove user configuration and cache directories
        for dir in "${HOME}/.config/${PKG_BASE_NAME}" \
                  "${HOME}/.config/${PKG_NAME}" \
                  "${HOME}/.cache/${PKG_BASE_NAME}" \
                  "${HOME}/.cache/${PKG_NAME}" \
                  "${HOME}/.local/share/${PKG_BASE_NAME}" \
                  "${HOME}/.local/share/${PKG_NAME}" \
                  "${HOME}/.${PKG_BASE_NAME}" \
                  "${HOME}/.${PKG_NAME}"; do
            if [ -d "$dir" ]; then
                rm -rf "$dir" 2>/dev/null || true
            fi
        done
        
        # Update desktop database
        if command -v update-desktop-database &>/dev/null; then
            sudo update-desktop-database 2>/dev/null || true
        fi
    fi
done

# Clean up apt cache and orphaned packages after removals
if grep -q "apt:" <<< "${FOUND_PACKAGES[*]}"; then
    echo -e "${BLUE}Cleaning up apt cache and orphaned packages...${NC}"
    sudo apt-get autoremove --purge -y 2>/dev/null || true
    sudo apt-get autoclean 2>/dev/null || true
    # Update desktop database
    if command -v update-desktop-database &>/dev/null; then
        sudo update-desktop-database 2>/dev/null || true
    fi
fi

echo -e "${GREEN}Uninstallation complete!${NC}"

