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

import graphviz
import subprocess
import os

# --- Configuration ---
# We define the EXACT filename with extension to avoid confusion
GV_FILENAME = 'security_architecture_wsl.gv'
DRAWIO_FILENAME = 'security_architecture_wsl_editable.drawio'

# Get absolute paths to ensure the subprocess finds them
GV_FILE_PATH = os.path.abspath(GV_FILENAME)
DRAWIO_FILE_PATH = os.path.abspath(DRAWIO_FILENAME)

# --- 1. DEFINE THE GRAPHVIZ DIAGRAM ---
dot = graphviz.Digraph(comment='Sovereign Cloud Security')
# Note: 'ortho' splines sometimes cause warnings with labels, but usually work
dot.attr(rankdir='LR', splines='ortho')

# Subgraph 1: The Problem
with dot.subgraph(name='cluster_problem') as c:
    c.attr(label='The Problem: IP-Based Security', style='filled', color='#fee2e2', fontsize='20')
    c.node('BadActor_1', 'Rogue Workload\n(Location: USA)', shape='box', style='filled', fillcolor='#e5e7eb')
    c.node('Firewall', 'Legacy Firewall\n(Checks IP Only)', shape='box', style='filled', fillcolor='#dbeafe', fontcolor='#1e40af')
    c.node('Data_1', 'Sovereign Data', shape='cylinder', style='filled', fillcolor='#fef3c7', fontcolor='#92400e')
    c.node('Breach', 'Security Breach!\nData Leaked', shape='note', style='filled', fillcolor='#fef2f2', fontcolor='#b91c1c')

    c.edge('BadActor_1', 'Firewall', label='VPN Spoof', style='dashed', color='#dc2626', fontcolor='#dc2626')
    c.edge('Firewall', 'Data_1', label='Allowed', color='#16a34a', penwidth='2')
    c.edge('Data_1', 'Breach', style='dotted', constraint='false')

# Subgraph 2: The Solution
with dot.subgraph(name='cluster_solution') as c:
    c.attr(label='The Solution: Hardware Trust', style='filled', color='#ecfdf5', fontsize='20')
    c.node('BadActor_2', 'Rogue Workload\n(Location: USA)', shape='box', style='filled', fillcolor='#e5e7eb')
    c.node('Verifier', 'Sovereign Verifier\n(Checks TPM + GPS)', shape='diamond', style='filled', fillcolor='#d1fae5', fontcolor='#065f46')
    c.node('Data_2', 'Sovereign Data', shape='cylinder', style='filled', fillcolor='#f3f4f6', fontcolor='#6b7280')
    c.node('Secure', 'Access Denied\nSpoofing Caught', shape='note', style='filled', fillcolor='#f0fdf4', fontcolor='#15803d')

    c.edge('BadActor_2', 'Verifier', label='Attestation Req', color='#6b7280')
    c.edge('Verifier', 'Data_2', label='Check Fails', color='#dc2626', style='dashed')
    c.edge('Verifier', 'Secure', label='Block', color='#16a34a', penwidth='2')


# --- 2. SAVE THE SOURCE FILE ---
try:
    # dot.save() forces the exact filename we defined above
    dot.save(GV_FILE_PATH)
    print(f"1. Successfully saved Graphviz source to:\n   {GV_FILE_PATH}")
except Exception as e:
    print(f"Error saving file: {e}")
    exit(1)


# --- 3. CONVERT TO DRAW.IO ---
try:
    print(f"2. Running converter...")

    # Run graphviz2drawio using the absolute paths
    command = ['graphviz2drawio', GV_FILE_PATH, '-o', DRAWIO_FILE_PATH]
    result = subprocess.run(command, check=True, capture_output=True, text=True)

    print("3. Conversion successful!")
    print(f"\n✅ YOUR FILE IS READY: {DRAWIO_FILENAME}")
    print("\nTo open this in Windows:")
    print(f"   Go to \\\\wsl$\\Ubuntu\\home\\ramki\\{DRAWIO_FILENAME}")
    print("   (Adjust 'Ubuntu' if your distro is named differently)")

except subprocess.CalledProcessError as e:
    print(f"\n--- Conversion Failed ---")
    print(f"Error output:\n{e.stderr}")
