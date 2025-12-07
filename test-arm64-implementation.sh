#!/bin/bash

# ARM64 Implementation Test Script for AegisEdgeAI
# This script validates that all ARM64 components are working correctly

set -euo pipefail

echo "=== AegisEdgeAI ARM64 Implementation Test ==="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Function to print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name - $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name - $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test 1: Architecture Detection
test_architecture() {
    echo -e "${BLUE}[TEST]${NC} Architecture Detection"
    
    local arch=$(uname -m)
    local expected_archs="aarch64|arm64"
    
    if [[ "$arch" =~ ^($expected_archs)$ ]]; then
        print_result "Architecture Detection" 0 "Detected ARM64 architecture: $arch"
    else
        print_result "Architecture Detection" 1 "Expected ARM64, got: $arch"
    fi
}

# Test 2: File Permissions and Executability
test_file_permissions() {
    echo -e "${BLUE}[TEST]${NC} File Permissions"
    
    local files=(
        "./zero-trust/system-setup.sh"
        "./zero-trust/system-setup-arm64.sh"
        "./zero-trust/tpm/swtpm.sh"
        "./zero-trust/tpm/tpm-ek-ak-persist.sh"
    )
    
    local all_executable=true
    local missing_files=""
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            if [ -x "$file" ]; then
                echo -e "  ${GREEN}✓${NC} $file is executable"
            else
                echo -e "  ${RED}✗${NC} $file is not executable"
                all_executable=false
            fi
        else
            echo -e "  ${YELLOW}?${NC} $file not found"
            missing_files="$missing_files $file"
            all_executable=false
        fi
    done
    
    if [ "$all_executable" = true ] && [ -z "$missing_files" ]; then
        print_result "File Permissions" 0 "All scripts are executable"
    else
        print_result "File Permissions" 1 "Some scripts missing or not executable:$missing_files"
    fi
}

# Test 3: Makefile ARM64 Detection
test_makefile_arm64() {
    echo -e "${BLUE}[TEST]${NC} Makefile ARM64 Support"
    
    if [ -f "./zero-trust/tpm/Makefile" ]; then
        cd ./zero-trust/tpm
        
        # Test makefile info target
        if make info > /tmp/make_info.log 2>&1; then
            local arch_detected=$(grep "Building for architecture" /tmp/make_info.log | cut -d: -f2 | xargs)
            
            if [[ "$arch_detected" =~ aarch64|arm64 ]]; then
                print_result "Makefile ARM64 Detection" 0 "Makefile correctly detects ARM64: $arch_detected"
            else
                print_result "Makefile ARM64 Detection" 1 "Makefile detection failed: $arch_detected"
            fi
        else
            print_result "Makefile ARM64 Detection" 1 "Makefile info target failed"
        fi
        
        cd - >/dev/null
    else
        print_result "Makefile ARM64 Detection" 1 "Makefile not found"
    fi
}

# Test 4: Python Dependencies
test_python_dependencies() {
    echo -e "${BLUE}[TEST]${NC} Python Dependencies ARM64 Compatibility"
    
    # Check for virtual environment first
    local python_cmd="python3"
    if [ -f ".venv/bin/python" ]; then
        python_cmd=".venv/bin/python"
        echo -e "  ${BLUE}INFO${NC} Using virtual environment: $python_cmd"
    elif ! command -v "$python_cmd" >/dev/null 2>&1; then
        python_cmd="python"
    fi
    
    if command -v "$python_cmd" >/dev/null 2>&1; then
        # Test key ARM64-compatible packages
        local packages=("cryptography" "OpenSSL" "requests" "flask")
        local all_imported=true
        
        for package in "${packages[@]}"; do
            if $python_cmd -c "import $package" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} $package imports successfully"
            else
                echo -e "  ${RED}✗${NC} $package failed to import"
                all_imported=false
            fi
        done
        
        if [ "$all_imported" = true ]; then
            print_result "Python Dependencies" 0 "All critical packages import successfully"
        else
            print_result "Python Dependencies" 1 "Some packages failed to import"
        fi
    else
        print_result "Python Dependencies" 1 "Python not found"
    fi
}

# Test 5: ARM64 Environment Script
test_arm64_environment() {
    echo -e "${BLUE}[TEST]${NC} ARM64 Environment Configuration"
    
    if [ -f "/etc/profile.d/arm64-tpm-env.sh" ]; then
        # Source the environment script
        if source /etc/profile.d/arm64-tpm-env.sh 2>/dev/null; then
            # Check if key environment variables are set
            if [ -n "${PREFIX:-}" ] && [ -n "${TPM2TOOLS_TCTI:-}" ]; then
                print_result "ARM64 Environment" 0 "Environment script loaded successfully (PREFIX=$PREFIX)"
            else
                print_result "ARM64 Environment" 1 "Environment variables not set correctly"
            fi
        else
            print_result "ARM64 Environment" 1 "Failed to source environment script"
        fi
    else
        print_result "ARM64 Environment" 1 "ARM64 environment script not found (run system-setup-arm64.sh first)"
    fi
}

# Test 6: TPM Tools Availability
test_tpm_tools() {
    echo -e "${BLUE}[TEST]${NC} TPM Tools Availability"
    
    local tools=("swtpm" "tpm2_createprimary" "tpm2_create" "tpm2_getcap")
    local tools_available=0
    local total_tools=${#tools[@]}
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $tool found at $(which $tool)"
            tools_available=$((tools_available + 1))
        else
            echo -e "  ${RED}✗${NC} $tool not found in PATH"
        fi
    done
    
    if [ $tools_available -eq $total_tools ]; then
        print_result "TPM Tools" 0 "All TPM tools available ($tools_available/$total_tools)"
    elif [ $tools_available -gt 0 ]; then
        print_result "TPM Tools" 1 "Partial TPM tools available ($tools_available/$total_tools)"
    else
        print_result "TPM Tools" 1 "No TPM tools found (run system-setup-arm64.sh first)"
    fi
}

# Test 7: Library Dependencies
test_library_dependencies() {
    echo -e "${BLUE}[TEST]${NC} TPM Library Dependencies"
    
    # Test by trying to link against libraries (more reliable than ldconfig parsing)
    local libraries=("tss2-esys" "tss2-mu" "ssl" "crypto")
    local lib_flags=("-ltss2-esys" "-ltss2-mu" "-lssl" "-lcrypto")
    local libs_found=0
    local total_libs=${#libraries[@]}
    
    # Create a simple test program
    local test_program="/tmp/lib_test_$$.c"
    cat > "$test_program" << 'EOF'
int main() { return 0; }
EOF
    
    for i in "${!libraries[@]}"; do
        local lib="${libraries[$i]}"
        local flag="${lib_flags[$i]}"
        
        # Try to compile with the library
        if gcc "$test_program" $flag -o "/tmp/test_$$" >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $lib linkable"
            libs_found=$((libs_found + 1))
            rm -f "/tmp/test_$$"
        else
            # Fallback to ldconfig check
            if ldconfig -p | grep -q "$lib"; then
                echo -e "  ${GREEN}✓${NC} $lib found in ldconfig"
                libs_found=$((libs_found + 1))
            else
                echo -e "  ${RED}✗${NC} $lib not available"
            fi
        fi
    done
    
    # Cleanup
    rm -f "$test_program"
    
    if [ $libs_found -eq $total_libs ]; then
        print_result "Library Dependencies" 0 "All required libraries available ($libs_found/$total_libs)"
    else
        print_result "Library Dependencies" 1 "Some libraries unavailable ($libs_found/$total_libs found)"
    fi
}

# Test 8: Compilation Test (if source available)
test_compilation() {
    echo -e "${BLUE}[TEST]${NC} ARM64 Compilation"
    
    if [ -f "./zero-trust/tpm/Makefile" ] && [ -f "./zero-trust/tpm/tpm-app-persist.c" ]; then
        # Source file already in tpm directory
        
        cd ./zero-trust/tpm
        
        # Clean and build
        if make clean >/dev/null 2>&1 && make >/dev/null 2>&1; then
            if [ -f "./tpm-app-persist" ]; then
                # Check if binary is ARM64
                local file_output=$(file ./tpm-app-persist)
                if echo "$file_output" | grep -q -i "aarch64\|arm64"; then
                    print_result "ARM64 Compilation" 0 "Successfully compiled ARM64 binary"
                else
                    print_result "ARM64 Compilation" 1 "Binary compiled but not ARM64: $file_output"
                fi
            else
                print_result "ARM64 Compilation" 1 "Compilation succeeded but binary not found"
            fi
        else
            print_result "ARM64 Compilation" 1 "Compilation failed (check build dependencies)"
        fi
        
        cd - >/dev/null
    else
        print_result "ARM64 Compilation" 1 "Source files not available for compilation test"
    fi
}

# Main test execution
main() {
    echo -e "Running on: ${YELLOW}$(uname -s) $(uname -m)${NC}"
    echo -e "Date: ${YELLOW}$(date)${NC}"
    echo ""
    
    # Run all tests
    test_architecture
    test_file_permissions
    test_makefile_arm64
    test_python_dependencies
    test_arm64_environment
    test_tpm_tools
    test_library_dependencies
    test_compilation
    
    # Print summary
    echo ""
    echo "=== Test Summary ==="
    echo -e "Total Tests: ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed! ARM64 implementation is ready.${NC}"
        exit 0
    elif [ $TESTS_PASSED -gt $TESTS_FAILED ]; then
        echo -e "${YELLOW}⚠ Most tests passed, but some issues found.${NC}"
        echo "Consider running system-setup-arm64.sh to resolve missing components."
        exit 1
    else
        echo -e "${RED}✗ Multiple test failures detected.${NC}"
        echo "Please run system-setup-arm64.sh and check the ARM64 documentation."
        exit 2
    fi
}

# Run tests
main "$@"