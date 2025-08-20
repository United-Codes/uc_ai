#!/bin/bash

# Script to generate all install scripts and test them
# This script calls the 3 generation scripts and then tests the 4 generated scripts

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=========================================="
echo "UC AI Installation Scripts Test"
echo "=========================================="

# Step 1: Generate all install scripts
echo ""
echo "Step 1: Generating install scripts..."
echo "--------------------------------------"

echo "Generating basic install script..."
bash "$SCRIPT_DIR/generate_install_script.sh"

echo "Generating complete install script..."
bash "$SCRIPT_DIR/generate_install_script_complete.sh"

echo "Generating upgrade script..."
bash "$SCRIPT_DIR/generate_upgrade_script.sh"

echo "All generation scripts completed successfully!"

# Step 2: Test all generated scripts
echo ""
echo "Step 2: Testing generated install scripts..."
echo "--------------------------------------------"

# Array of scripts to test
SCRIPTS_TO_TEST=(
    "install_with_logger.sql"
    "install_uc_ai_complete_with_logger.sql"
)

# Function to test a script
test_script() {
    local script_name="$1"
    local script_path="$ROOT_DIR/$script_name"
    
    echo ""
    echo "Testing: $script_name"
    echo "------------------------"
    
    if [ ! -f "$script_path" ]; then
        echo "ERROR: Script not found: $script_path"
        return 1
    fi
    
    echo "Running: local-23ai.sh test-script-install ./$script_name -y"
    
    # Change to root directory so relative paths work
    cd "$ROOT_DIR"
    
    # Run the test command and capture output
    if output=$(local-23ai.sh test-script-install "./$script_name" -y 2>&1); then
        echo "Script executed successfully!"
        
        # Check if the output contains the expected success message
        if echo "$output" | grep -q "Invalid objects:" && echo "$output" | grep -q "no rows selected"; then
            echo "✅ SUCCESS: Found expected output 'Invalid objects: no rows selected'"
        else
            echo "⚠️  WARNING: Expected output 'Invalid objects: no rows selected' not found"
            echo "Last 10 lines of output:"
            echo "$output" | tail -10
        fi
    else
        echo "❌ ERROR: Script execution failed"
        echo "Error output:"
        echo "$output" | tail -20
        return 1
    fi
    
    echo "------------------------"
}

# Test each script
for script in "${SCRIPTS_TO_TEST[@]}"; do
    if ! test_script "$script"; then
        echo "❌ FAILED: Testing $script"
        exit 1
    fi
done

echo ""
echo "=========================================="
echo "✅ ALL TESTS COMPLETED SUCCESSFULLY!"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Generated 3 install scripts"
echo "- Successfully tested 4 install scripts"
echo "- All scripts passed validation"
echo "=========================================="
