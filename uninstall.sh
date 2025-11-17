#!/bin/bash

# uninstall.sh - Uninstall utilities from flatpak, snap, and apt
# Usage: ./uninstall.sh <incomplete-utility-name>

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <incomplete-utility-name>"
    echo "Example: $0 firefox"
    exit 1
fi

SEARCH_TERM="$1"
FOUND_PACKAGES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Searching for '${SEARCH_TERM}' in package managers...${NC}\n"

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
            FOUND_PACKAGES+=("flatpak:$app_id")
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
                FOUND_PACKAGES+=("snap:$SNAP_NAME")
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
                FOUND_PACKAGES+=("apt:$PKG_NAME")
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
        sudo apt remove --purge -y "$PKG_NAME" 2>/dev/null || {
            echo -e "${RED}Failed to uninstall apt package: ${PKG_NAME}${NC}"
        }
    fi
done

# Clean up apt cache after removals
if grep -q "apt:" <<< "${FOUND_PACKAGES[*]}"; then
    echo -e "${BLUE}Cleaning up apt cache...${NC}"
    sudo apt autoremove -y 2>/dev/null || true
    sudo apt autoclean 2>/dev/null || true
fi

echo -e "${GREEN}Uninstallation complete!${NC}"

