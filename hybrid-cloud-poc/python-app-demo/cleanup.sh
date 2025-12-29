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

# Unified-Identity - Setup: Cleanup script for Python app demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Unified-Identity - Setup: Cleaning up Python App Demo"
echo ""

# Force QUIET=0 to ensure cleanup output is visible
export QUIET=0

"${PROJECT_ROOT}/scripts/stop-unified-identity.sh"

echo "Removing SVID output files..."
rm -rf /tmp/svid-dump /tmp/svid.pem /tmp/svid.key /tmp/svid_attested_claims.json 2>/dev/null || true

echo ""
echo "✓ Cleanup complete"
