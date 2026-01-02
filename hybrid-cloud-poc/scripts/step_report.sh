#!/bin/bash

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Structured Step/Sub-Step Reporting for CI Test Runner
# Output format: [STEP:<script>:<step>:<substep>:<status>] <message>
# Status: START | SUCCESS | FAILURE
#
# This enables ci_test_runner.py to precisely identify where failures occur.

# Get the calling script name (without path and extension)
_STEP_REPORT_SCRIPT="${STEP_REPORT_SCRIPT:-$(basename "${BASH_SOURCE[1]:-unknown}" .sh)}"

# Current step/substep tracking
_CURRENT_STEP=""
_CURRENT_SUBSTEP=""

# Report start of a step
# Usage: report_step_start <step_number> <message>
report_step_start() {
    local step="$1"
    local msg="$2"
    _CURRENT_STEP="$step"
    _CURRENT_SUBSTEP="0"
    echo "[STEP:${_STEP_REPORT_SCRIPT}:${step}:0:START] ${msg}"
}

# Report start of a sub-step
# Usage: report_substep_start <substep_number> <message>
report_substep_start() {
    local substep="$1"
    local msg="$2"
    _CURRENT_SUBSTEP="$substep"
    echo "[STEP:${_STEP_REPORT_SCRIPT}:${_CURRENT_STEP}:${substep}:START] ${msg}"
}

# Report success of current step/substep
# Usage: report_step_success [message]
report_step_success() {
    local msg="${1:-Step completed}"
    echo "[STEP:${_STEP_REPORT_SCRIPT}:${_CURRENT_STEP}:${_CURRENT_SUBSTEP}:SUCCESS] ✓ ${msg}"
}

# Report failure and exit (fail-fast)
# Usage: report_step_failure <message>
report_step_failure() {
    local msg="$1"
    echo "[STEP:${_STEP_REPORT_SCRIPT}:${_CURRENT_STEP}:${_CURRENT_SUBSTEP}:FAILURE] ✗ ${msg}"
    # Fail-fast: exit immediately on failure
    exit 1
}

# Wrap a command - reports success/failure based on exit code
# Usage: run_step <step> <message> <command> [args...]
run_step() {
    local step="$1"
    local msg="$2"
    shift 2
    
    report_step_start "$step" "$msg"
    if "$@"; then
        report_step_success "$msg"
        return 0
    else
        report_step_failure "$msg failed (exit code: $?)"
        return 1  # won't reach here due to exit in report_step_failure
    fi
}

# Wrap a substep command
# Usage: run_substep <substep> <message> <command> [args...]
run_substep() {
    local substep="$1"
    local msg="$2"
    shift 2
    
    report_substep_start "$substep" "$msg"
    if "$@"; then
        report_step_success "$msg"
        return 0
    else
        report_step_failure "$msg failed (exit code: $?)"
        return 1
    fi
}

# Check if a condition is true, fail if not
# Usage: check_step <step> <message> <condition_command> [args...]
check_step() {
    local step="$1"
    local msg="$2"
    shift 2
    
    report_step_start "$step" "Checking: $msg"
    if "$@"; then
        report_step_success "$msg"
        return 0
    else
        report_step_failure "$msg"
        return 1
    fi
}

# Export current script name for sub-shells
export STEP_REPORT_SCRIPT="${_STEP_REPORT_SCRIPT}"
