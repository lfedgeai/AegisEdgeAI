#!/usr/bin/env python3
"""
Generate an interactive HTML UI for visualizing end-to-end workflow logs.
"""

import re
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Component colors for visualization
COMPONENT_COLORS = {
    'SPIRE_AGENT': '#4A90E2',      # Blue
    'SPIRE_SERVER': '#7B68EE',     # Medium Slate Blue
    'TPM_PLUGIN': '#50C878',       # Emerald Green
    'RUST_KEYLIME': '#FF6B6B',     # Coral Red
    'KEYLIME_VERIFIER': '#FFA500', # Orange
    'MOBILE_SENSOR': '#9B59B6',    # Purple
    'WORKLOAD': '#E74C3C',         # Red
}

COMPONENT_NAMES = {
    'SPIRE_AGENT': 'SPIRE Agent',
    'SPIRE_SERVER': 'SPIRE Server',
    'TPM_PLUGIN': 'TPM Plugin Server',
    'RUST_KEYLIME': 'rust-keylime Agent',
    'KEYLIME_VERIFIER': 'Keylime Verifier',
    'MOBILE_SENSOR': 'Mobile Location Verification',
    'WORKLOAD': 'Workload',
}

PHASE_DEFINITIONS = {
    'Setup': {
        'name': 'Initial Setup & TPM Preparation',
        'components': ['TPM_PLUGIN', 'RUST_KEYLIME'],
        'keywords': ['App Key', 'registered', 'activated']
    },
    'Attestation': {
        'name': 'SPIRE Agent Attestation (Agent SVID Generation)',
        'components': ['SPIRE_AGENT', 'TPM_PLUGIN', 'RUST_KEYLIME', 'SPIRE_SERVER', 'KEYLIME_VERIFIER', 'MOBILE_SENSOR'],
        'keywords': ['SovereignAttestation', 'TPM Quote', 'certificate', 'Delegated', 'Keylime', 'Agent SVID']
    },
    'Verification': {
        'name': 'Workload SVID Generation',
        'components': ['SPIRE_AGENT', 'SPIRE_SERVER'],
        'keywords': ['Workload', 'python-app', 'BatchNewX509SVID']
    }
}


def parse_timestamp(ts_str):
    """Parse timestamp string to datetime object."""
    # Clean up timestamp string
    ts_str = ts_str.strip()
    
    # Try various timestamp formats
    formats = [
        '%Y-%m-%dT%H:%M:%S.%f%z',      # ISO with microseconds and timezone
        '%Y-%m-%dT%H:%M:%S%z',         # ISO with timezone
        '%Y-%m-%dT%H:%M:%S.%f',        # ISO with microseconds
        '%Y-%m-%dT%H:%M:%S',           # ISO basic
        '%Y-%m-%d %H:%M:%S,%f',        # Python logging format
        '%Y-%m-%d %H:%M:%S.%f',        # Alternative with dot
        '%Y-%m-%d %H:%M:%S',           # Simple format
    ]
    
    # Handle timezone offset manually if present
    tz_match = re.search(r'([+-]\d{4})$', ts_str)
    tz_offset = None
    if tz_match:
        tz_str = tz_match.group(1)
        ts_str = ts_str[:-len(tz_str)]
        # Convert +0100 to timedelta
        hours = int(tz_str[1:3])
        minutes = int(tz_str[3:5])
        sign = -1 if tz_str[0] == '-' else 1
        tz_offset = timezone(timedelta(hours=sign*hours, minutes=sign*minutes))
    
    for fmt in formats:
        try:
            dt = datetime.strptime(ts_str, fmt)
            if tz_offset:
                dt = dt.replace(tzinfo=tz_offset)
            return dt
        except ValueError:
            continue
    
    # If all fail, return current time
    return datetime.now()


def extract_logs_from_files():
    """Extract logs from component log files."""
    logs = []
    log_files = {
        'TPM_PLUGIN': '/tmp/tpm-plugin-server.log',
        'SPIRE_AGENT': '/tmp/spire-agent.log',
        'SPIRE_SERVER': '/tmp/spire-server.log',
        'KEYLIME_VERIFIER': '/tmp/keylime-verifier.log',
        'RUST_KEYLIME': '/tmp/rust-keylime-agent.log',
        'MOBILE_SENSOR': '/tmp/mobile-sensor-microservice.log',
    }
    
    # Patterns for extracting relevant log lines
    patterns = {
        'TPM_PLUGIN': r'App Key|TPM Quote|Delegated|certificate|request|response|Unified-Identity',
        'SPIRE_AGENT': r'TPM Plugin|SovereignAttestation|TPM Quote|certificate|Agent SVID|Workload|Unified-Identity|attest|python-app|BatchNewX509SVID',
        'SPIRE_SERVER': r'SovereignAttestation|Keylime Verifier|AttestedClaims|Agent SVID|Workload|Unified-Identity|attest|python-app|Skipping.*Keylime',
        'KEYLIME_VERIFIER': r'Processing|Verifying|certificate|quote|mobile|sensor|Unified-Identity|Verification|App Key|Verification successful',
        'RUST_KEYLIME': r'registered|activated|Delegated|certificate|quote|geolocation|Unified-Identity',
        'MOBILE_SENSOR': r'verify|CAMARA|sensor|verification|request|response',
    }
    
    for component, log_file in log_files.items():
        if not Path(log_file).exists():
            continue
        
        pattern = patterns.get(component, '.*')
        
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                if re.search(pattern, line, re.IGNORECASE):
                    # Extract timestamp (various formats)
                    timestamp = None
                    
                    # Try ISO format first (SPIRE logs)
                    ts_match = re.search(r'(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:[+-]\d{4})?)', line)
                    if ts_match:
                        ts_str = ts_match.group(1)
                        timestamp = parse_timestamp(ts_str)
                    else:
                        # Try Python logging format (YYYY-MM-DD HH:MM:SS,mmm)
                        ts_match = re.search(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:,\d+)?)', line)
                        if ts_match:
                            ts_str = ts_match.group(1)
                            timestamp = parse_timestamp(ts_str)
                        else:
                            # Rust logs might not have timestamps in the line, use file mtime or current time
                            # For now, use a relative timestamp based on line number
                            timestamp = datetime.now()
                    
                    logs.append({
                        'timestamp': timestamp,
                        'component': component,
                        'message': line.strip(),
                        'raw': line
                    })
    
    # Sort by timestamp
    logs.sort(key=lambda x: x['timestamp'])
    
    return logs


def categorize_logs(logs):
    """Categorize logs into phases."""
    phases = {phase: [] for phase in PHASE_DEFINITIONS.keys()}
    
    for log in logs:
        component = log['component']
        message = log['message']
        
        # Determine phase based on component and keywords
        assigned = False
        
        for phase_name, phase_def in PHASE_DEFINITIONS.items():
            if component in phase_def['components']:
                # Check if message matches phase keywords
                if any(keyword.lower() in message.lower() for keyword in phase_def['keywords']):
                    phases[phase_name].append(log)
                    assigned = True
                    break
        
        # If not assigned, try to assign based on message content
        if not assigned:
            if 'Workload' in message or 'python-app' in message or 'BatchNewX509SVID' in message:
                phases['Verification'].append(log)
            elif 'SovereignAttestation' in message or 'Agent SVID' in message or 'Keylime' in message:
                phases['Attestation'].append(log)
            elif 'App Key' in message or 'registered' in message or 'activated' in message:
                phases['Setup'].append(log)
    
    return phases


def generate_html(phases, all_logs):
    """Generate HTML visualization."""
    
    # Calculate timeline bounds
    if all_logs:
        start_time = min(log['timestamp'] for log in all_logs)
        end_time = max(log['timestamp'] for log in all_logs)
        duration = (end_time - start_time).total_seconds()
    else:
        start_time = datetime.now()
        end_time = datetime.now()
        duration = 1
    
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Sovereign Unified Identity - Workflow Visualization</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            color: #333;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }}
        
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        .header h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
        }}
        
        .header p {{
            font-size: 1.1em;
            opacity: 0.9;
        }}
        
        .stats {{
            display: flex;
            justify-content: space-around;
            padding: 20px;
            background: #f8f9fa;
            border-bottom: 2px solid #e9ecef;
        }}
        
        .stat {{
            text-align: center;
        }}
        
        .stat-value {{
            font-size: 2em;
            font-weight: bold;
            color: #667eea;
        }}
        
        .stat-label {{
            color: #666;
            margin-top: 5px;
        }}
        
        .phases {{
            padding: 20px;
        }}
        
        .phase {{
            margin-bottom: 40px;
            border: 2px solid #e9ecef;
            border-radius: 8px;
            overflow: hidden;
        }}
        
        .phase-header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.3s;
        }}
        
        .phase-header:hover {{
            background: linear-gradient(135deg, #764ba2 0%, #667eea 100%);
        }}
        
        .phase-header h2 {{
            font-size: 1.5em;
        }}
        
        .phase-toggle {{
            font-size: 1.2em;
            transition: transform 0.3s;
        }}
        
        .phase-content {{
            padding: 20px;
            display: none;
        }}
        
        .phase-content.active {{
            display: block;
        }}
        
        .timeline {{
            position: relative;
            padding: 20px 0;
        }}
        
        .timeline-line {{
            position: absolute;
            left: 50px;
            top: 0;
            bottom: 0;
            width: 3px;
            background: linear-gradient(to bottom, #667eea, #764ba2);
        }}
        
        .log-entry {{
            position: relative;
            margin-bottom: 20px;
            padding-left: 80px;
            animation: fadeIn 0.5s ease-in;
        }}
        
        @keyframes fadeIn {{
            from {{
                opacity: 0;
                transform: translateX(-20px);
            }}
            to {{
                opacity: 1;
                transform: translateX(0);
            }}
        }}
        
        .log-dot {{
            position: absolute;
            left: 42px;
            top: 10px;
            width: 16px;
            height: 16px;
            border-radius: 50%;
            border: 3px solid white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }}
        
        .log-card {{
            background: white;
            border-left: 4px solid;
            border-radius: 6px;
            padding: 15px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            transition: transform 0.2s, box-shadow 0.2s;
        }}
        
        .log-card:hover {{
            transform: translateX(5px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }}
        
        .log-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }}
        
        .log-component {{
            font-weight: bold;
            font-size: 1.1em;
            padding: 5px 12px;
            border-radius: 20px;
            color: white;
            display: inline-block;
        }}
        
        .log-time {{
            color: #666;
            font-size: 0.9em;
        }}
        
        .log-message {{
            color: #333;
            line-height: 1.6;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            word-wrap: break-word;
        }}
        
        .flow-arrow {{
            text-align: center;
            color: #667eea;
            font-size: 1.5em;
            margin: 10px 0;
            font-weight: bold;
        }}
        
        .component-filter {{
            padding: 20px;
            background: #f8f9fa;
            border-bottom: 2px solid #e9ecef;
        }}
        
        .filter-buttons {{
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }}
        
        .filter-btn {{
            padding: 8px 16px;
            border: 2px solid #667eea;
            background: white;
            color: #667eea;
            border-radius: 20px;
            cursor: pointer;
            transition: all 0.3s;
        }}
        
        .filter-btn:hover {{
            background: #667eea;
            color: white;
        }}
        
        .filter-btn.active {{
            background: #667eea;
            color: white;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ Sovereign Unified Identity</h1>
            <p>End-to-End Workflow Visualization</p>
            <p style="margin-top: 10px; font-size: 0.9em;">Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
        
        <div class="stats">
            <div class="stat">
                <div class="stat-value">{len(all_logs)}</div>
                <div class="stat-label">Total Log Entries</div>
            </div>
            <div class="stat">
                <div class="stat-value">{len(phases)}</div>
                <div class="stat-label">Phases</div>
            </div>
            <div class="stat">
                <div class="stat-value">{duration:.1f}s</div>
                <div class="stat-label">Total Duration</div>
            </div>
        </div>
        
        <div class="component-filter">
            <h3 style="margin-bottom: 10px;">Filter by Component:</h3>
            <div class="filter-buttons">
                <button class="filter-btn active" data-component="all">All Components</button>
"""
    
    # Add filter buttons for each component
    for comp_id, comp_name in COMPONENT_NAMES.items():
        html += f'                <button class="filter-btn" data-component="{comp_id}">{comp_name}</button>\n'
    
    html += """            </div>
        </div>
        
        <div class="phases">
"""
    
    # Generate phase sections
    for phase_name, phase_def in PHASE_DEFINITIONS.items():
        phase_logs = phases.get(phase_name, [])
        
        html += f"""            <div class="phase" data-phase="{phase_name}">
                <div class="phase-header" onclick="togglePhase('{phase_name}')">
                    <h2>{phase_name}: {phase_def['name']}</h2>
                    <span class="phase-toggle" id="toggle-{phase_name}">▼</span>
                </div>
                <div class="phase-content" id="content-{phase_name}">
                    <div class="timeline">
                        <div class="timeline-line"></div>
"""
        
        if phase_logs:
            prev_component = None
            for log in phase_logs:
                component = log['component']
                timestamp = log['timestamp']
                message = log['message']
                
                # Clean up message (remove excessive whitespace, truncate if too long)
                clean_msg = ' '.join(message.split())
                if len(clean_msg) > 200:
                    clean_msg = clean_msg[:200] + '...'
                
                color = COMPONENT_COLORS.get(component, '#666')
                comp_name = COMPONENT_NAMES.get(component, component)
                
                # Add flow arrow if component changed
                if prev_component and prev_component != component:
                    html += '                        <div class="flow-arrow">↓</div>\n'
                
                html += f"""                        <div class="log-entry" data-component="{component}">
                            <div class="log-dot" style="background-color: {color};"></div>
                            <div class="log-card" style="border-left-color: {color};">
                                <div class="log-header">
                                    <span class="log-component" style="background-color: {color};">{comp_name}</span>
                                    <span class="log-time">{timestamp.strftime('%H:%M:%S.%f')[:-3]}</span>
                                </div>
                                <div class="log-message">{clean_msg}</div>
                            </div>
                        </div>
"""
                prev_component = component
        else:
            html += '                        <p style="padding: 20px; color: #666;">No logs found for this phase.</p>\n'
        
        html += """                    </div>
                </div>
            </div>
"""
    
    html += """        </div>
    </div>
    
    <script>
        // Toggle phase visibility
        function togglePhase(phaseName) {
            const content = document.getElementById('content-' + phaseName);
            const toggle = document.getElementById('toggle-' + phaseName);
            
            if (content.classList.contains('active')) {
                content.classList.remove('active');
                toggle.textContent = '▶';
            } else {
                content.classList.add('active');
                toggle.textContent = '▼';
            }
        }
        
        // Expand all phases by default
        document.addEventListener('DOMContentLoaded', function() {
            const phases = ['Setup', 'Attestation', 'Verification'];
            phases.forEach(phase => {
                const content = document.getElementById('content-' + phase);
                const toggle = document.getElementById('toggle-' + phase);
                if (content) {
                    content.classList.add('active');
                    toggle.textContent = '▼';
                }
            });
        });
        
        // Component filtering
        document.querySelectorAll('.filter-btn').forEach(btn => {
            btn.addEventListener('click', function() {
                const component = this.dataset.component;
                
                // Update active button
                document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
                this.classList.add('active');
                
                // Filter log entries
                document.querySelectorAll('.log-entry').forEach(entry => {
                    if (component === 'all' || entry.dataset.component === component) {
                        entry.style.display = 'block';
                    } else {
                        entry.style.display = 'none';
                    }
                });
            });
        });
    </script>
</body>
</html>
"""
    
    return html


def main():
    """Main function."""
    print("Generating workflow visualization...")
    
    # Extract logs
    print("  Extracting logs from component files...")
    all_logs = extract_logs_from_files()
    print(f"  Found {len(all_logs)} log entries")
    
    # Categorize into phases
    print("  Categorizing logs into phases...")
    phases = categorize_logs(all_logs)
    for phase_name, phase_logs in phases.items():
        print(f"    {phase_name}: {len(phase_logs)} entries")
    
    # Generate HTML
    print("  Generating HTML visualization...")
    html = generate_html(phases, all_logs)
    
    # Write to file
    output_file = '/tmp/workflow_visualization.html'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(html)
    
    print(f"\n✓ Workflow visualization generated: {output_file}")
    print(f"  Open in browser: file://{output_file}")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())

