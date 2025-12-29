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
GV_FILENAME = 'stage1_identity.gv'
DRAWIO_FILENAME = 'stage1_identity_editable.drawio'

# Absolute paths
GV_FILE_PATH = os.path.abspath(GV_FILENAME)
DRAWIO_FILE_PATH = os.path.abspath(DRAWIO_FILENAME)

# --- 1. DEFINE THE DIAGRAM ---
dot = graphviz.Digraph(comment='Stage 1: Identity Foundation')
dot.attr(rankdir='LR', splines='ortho')

# CLUSTER 1: The Problem (Implicit Trust)
with dot.subgraph(name='cluster_problem') as c:
    c.attr(label='Stage 1 Problem: Implicit Trust\n(Network = Permissive)', style='filled', color='#fee2e2', fontsize='20')

    # Nodes
    c.node('Hacker', 'Attacker\n(Shell Access)', shape='circle', style='filled', fillcolor='#b91c1c', fontcolor='white')
    c.node('WebApp_1', 'Compromised\nWeb Pod', shape='box', style='filled', fillcolor='#fca5a5') # Red tint
    c.node('DB_1', 'Customer DB', shape='cylinder', style='filled', fillcolor='#fef3c7', fontcolor='#92400e')

    # Edges
    c.edge('Hacker', 'WebApp_1', label='Exploit', color='#b91c1c')
    c.edge('WebApp_1', 'DB_1', label='Allowed Access\n(IP is trusted)', color='#b91c1c', penwidth='2')


# CLUSTER 2: The Solution (SPIFFE/SPIRE Identity)
with dot.subgraph(name='cluster_solution') as c:
    c.attr(label='Stage 1 Solution: Identity (SPIFFE)\n(No ID = No Access)', style='filled', color='#ecfdf5', fontsize='20')

    # Nodes
    c.node('Spire', 'SPIRE Server\n(Trust Authority)', shape='hexagon', style='filled', fillcolor='#dbeafe', fontcolor='#1e40af')
    c.node('WebApp_2', 'Compromised\nWeb Pod', shape='box', style='filled', fillcolor='#fca5a5')
    c.node('Sidecar', 'SPIRE Agent\n(No SVID Issued)', shape='ellipse', style='filled', fillcolor='#e5e7eb', fontcolor='#374151')
    c.node('DB_2', 'Customer DB\n(mTLS Only)', shape='cylinder', style='filled', fillcolor='#f3f4f6', fontcolor='#6b7280')

    # Edges
    c.edge('Spire', 'Sidecar', label='Attestation Fails\n(Bad Hash)', color='#b91c1c', style='dashed')
    c.edge('WebApp_2', 'DB_2', label='TLS Handshake Rejected\n(Missing Certificate)', color='#059669', penwidth='2')
    # Invisible edge to force layout if needed, or logical connection
    c.edge('Sidecar', 'WebApp_2', style='invis')

# --- 2. SAVE & CONVERT ---
try:
    dot.save(GV_FILE_PATH)
    print(f"1. Saved source: {GV_FILENAME}")

    command = ['graphviz2drawio', GV_FILE_PATH, '-o', DRAWIO_FILE_PATH]
    subprocess.run(command, check=True, capture_output=True, text=True)

    print(f"2. Converted to: {DRAWIO_FILENAME}")
    print(f"\n✅ SUCCESS! Open {DRAWIO_FILENAME} in Draw.io")

except subprocess.CalledProcessError as e:
    print(f"Error: {e.stderr}")
