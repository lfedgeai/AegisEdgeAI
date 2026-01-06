#!/usr/bin/env python3
#
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

import requests
import os
import sys

# Usage: python3 create_github_issues.py <GITHUB_TOKEN>

TOKEN = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("GITHUB_TOKEN")
REPO = "lfedgeai/AegisSovereignAI"
HEADERS = {
    "Authorization": f"token {TOKEN}",
    "Accept": "application/vnd.github.v3+json"
}

PRIO_LABELS = [
    {"name": "prio:P1", "color": "d73a4a", "description": "Critical - Required for production readiness"},
    {"name": "prio:P2", "color": "e99695", "description": "Important - Should complete for 1.0 release"},
    {"name": "prio:P3", "color": "f9d0c4", "description": "Nice-to-have - Can defer to future releases"}
]

# Mapping of issues to their priorities based on the roadmap
ISSUE_PRIORITIES = {
    # P1: Mandatories / Critical Technical Debt
    "P1": [130, 153],
    
    # P2: Production Hardening
    "P2": [
        139, 140, # Downgraded from P1: substantial work, feature-flagged
        156, 160, 161, 158, 157, 147, 148, 142, 143, 144, 145, 
        152, 136, 135, 127, 137, 149, 134, 132, 131, 128, 129, 
        154, 155, 163, 133, 138, 150, 184, 185, 186, 187, 188, 189
    ],
    
    # P3: Long-term / Optional
    "P3": [162, 159, 190]
}

def setup_labels():
    for label in PRIO_LABELS:
        url = f"https://api.github.com/repos/{REPO}/labels"
        requests.post(url, headers=HEADERS, json=label)

def update_issue_priority(issue_num, prio):
    url = f"https://api.github.com/repos/{REPO}/issues/{issue_num}"
    label_name = f"prio:{prio}"
    
    # Get current labels to preserve them
    resp = requests.get(url, headers=HEADERS)
    if resp.status_code == 200:
        current_labels = [l['name'] for l in resp.json().get('labels', [])]
        if label_name not in current_labels:
            current_labels = [l for l in current_labels if not l.startswith("prio:")]
            current_labels.append(label_name)
            requests.patch(url, headers=HEADERS, json={"labels": current_labels})
            print(f"Updated Issue #{issue_num} with {label_name}")

def post_comment(issue_num, comment):
    url = f"https://api.github.com/repos/{REPO}/issues/{issue_num}/comments"
    resp = requests.post(url, headers=HEADERS, json={"body": comment})
    if resp.status_code == 201:
        print(f"Commented on Issue #{issue_num}")
    else:
        print(f"Failed to comment on Issue #{issue_num}: {resp.status_code}")

RATIONALE = """### 🧐 Priority Rationale (P2 Downgrade)
This task has been moved from P1 to P2 to ensure high-velocity upstreaming:
1. **Focus on Protocol Acceptance**: The core value is the Unified Identity trust model. TSS library integration is an implementation detail that can follow once core plugins are accepted.
2. **Reduced Integration Friction**: Using standard `tpm2-tools` subprocesses minimizes dependency complexity for initial upstream reviewers.
3. **Safety**: The feature is protected by feature flags, allowing for a phased hardening approach post-merge.
"""

if __name__ == "__main__":
    if not TOKEN:
        print("Error: GITHUB_TOKEN not found in environment or arguments.")
        sys.exit(1)
    
    # We already ran setup_labels and update_issue_priority in the previous step.
    # Now just adding the comments for the P2 rationale.
    
    print("Posting priority rationale to TSS issues...")
    for issue_num in [139, 140]:
        post_comment(issue_num, RATIONALE)
