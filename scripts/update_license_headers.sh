#!/bin/bash

# Script to unify and update license headers in .pks files
# 
# Detection strategy: Uses "https://www.united-codes.com" as an anchor marker
# since this URL is present in all license blocks and unlikely to change.
# The script finds the comment block containing this URL and replaces it entirely.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR/../src/packages"

# The license header template
# Modify these variables to update the license header in the future
LICENSE_TITLE="UC AI"
LICENSE_DESCRIPTION="PL/SQL SDK to integrate AI capabilities into Oracle databases."
LICENSE_YEAR="2025-present"
LICENSE_COMPANY="United Codes"


# NEVER CHANGE THIS URL - it is our detection marker
LICENSE_URL="https://www.united-codes.com"

# Function to update license header in a file
update_license_header() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    
    # Check if file contains the United Codes URL (our detection marker)
    if ! grep -q "https://www.united-codes.com" "$file"; then
        echo "  [SKIP] No license block found (missing united-codes.com URL)"
        return 0
    fi
    
    # Create a temporary file
    local tmp_file
    tmp_file=$(mktemp)
    
    # Use perl for reliable multiline replacement
    # The regex finds comment blocks /** ... */ containing united-codes.com
    perl -0777 -pe '
        s{
            (^\s*)           # Capture leading whitespace
            /\*\*            # Start of comment block
            .*?              # Any content (non-greedy)
            united-codes\.com # Our marker URL
            .*?              # Any content after URL (non-greedy)
            \*/              # End of comment block
        }{$1/**
  * '"${LICENSE_TITLE}"'
  * '"${LICENSE_DESCRIPTION}"'
  * 
  * Licensed under the GNU Lesser General Public License v3.0
  * Copyright (c) '"${LICENSE_YEAR}"' '"${LICENSE_COMPANY}"'
  * '"${LICENSE_URL}"'
  */}xms' "$file" > "$tmp_file"
    
    # Check if file was modified
    if diff -q "$file" "$tmp_file" > /dev/null 2>&1; then
        echo "  [UNCHANGED] License header already up to date"
        rm "$tmp_file"
    else
        mv "$tmp_file" "$file"
        echo "  [UPDATED] License header replaced"
    fi
}

# Main execution
main() {
    echo "License Header Update Script"
    echo "============================="
    echo ""
    echo "License settings:"
    echo "  Title:       $LICENSE_TITLE"
    echo "  Description: $LICENSE_DESCRIPTION"
    echo "  Year:        $LICENSE_YEAR"
    echo "  Company:     $LICENSE_COMPANY"
    echo "  URL:         $LICENSE_URL"
    echo ""
    echo "Processing .pks files in: $PACKAGES_DIR"
    echo ""
    
    # Check if packages directory exists
    if [[ ! -d "$PACKAGES_DIR" ]]; then
        echo "Error: Packages directory not found: $PACKAGES_DIR"
        exit 1
    fi
    
    # Process all .pks files
    local count=0
    local updated=0
    
    for file in "$PACKAGES_DIR"/*.pks; do
        if [[ -f "$file" ]]; then
            count=$((count + 1))
            filename=$(basename "$file")
            echo "Processing: $filename"
            
            # Capture output to check if updated
            result=$(update_license_header "$file")
            echo "$result"
            
            if [[ "$result" == *"[UPDATED]"* ]]; then
                updated=$((updated + 1))
            fi
        fi
    done
    
    echo ""
    echo "============================="
    echo "Summary: Processed $count files, updated $updated"
}

# Run main function
main "$@"
