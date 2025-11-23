# Workflow Visualization UI

## Overview

The workflow visualization UI provides an interactive HTML-based visualization of the end-to-end workflow logs from the Verification test suite. It displays logs in a timeline format, grouped by phases, with color-coded components and interactive filtering.

## Features

- **Timeline Visualization**: Chronological display of all workflow events
- **Phase Grouping**: Logs organized by Setup (Setup), Attestation (Agent SVID), Verification (Workload SVID)
- **Component Color Coding**: Each component has a distinct color for easy identification
- **Interactive Filtering**: Filter logs by component type
- **Expandable Phases**: Click phase headers to expand/collapse sections
- **Flow Indicators**: Visual arrows showing component transitions

## Usage

### Automatic Generation

The visualization is automatically generated when you run the Verification test suite:

```bash
./test_phase3_complete.sh --no-pause
```

After the test completes, you'll see:
```
✓ Interactive workflow visualization generated: /tmp/workflow_visualization.html
  Open in browser: file:///tmp/workflow_visualization.html
```

### Manual Generation

You can also generate the visualization manually:

```bash
python3 generate_workflow_ui.py
```

This will create `/tmp/workflow_visualization.html` which you can open in any web browser.

## Components

The visualization tracks the following components:

- **SPIRE Agent** (Blue): Handles workload requests and agent attestation
- **SPIRE Server** (Purple): Issues SVIDs and coordinates verification
- **TPM Plugin Server** (Green): Manages TPM operations
- **rust-keylime Agent** (Red): Provides TPM quotes and delegated certification
- **Keylime Verifier** (Orange): Verifies TPM evidence and certificates
- **Mobile Location Verification** (Purple): Verifies geolocation via CAMARA APIs

## Viewing the Visualization

1. Open the generated HTML file in your web browser:
   ```bash
   xdg-open /tmp/workflow_visualization.html
   # or
   firefox /tmp/workflow_visualization.html
   # or
   google-chrome /tmp/workflow_visualization.html
   ```

2. Use the component filter buttons at the top to show/hide specific components

3. Click on phase headers to expand/collapse phase sections

4. Hover over log entries to see full details

## Requirements

- Python 3.6+
- Component log files in `/tmp/`:
  - `/tmp/tpm-plugin-server.log`
  - `/tmp/spire-agent.log`
  - `/tmp/spire-server.log`
  - `/tmp/keylime-verifier.log`
  - `/tmp/rust-keylime-agent.log`
  - `/tmp/mobile-sensor-microservice.log`

## Troubleshooting

If the visualization is empty or missing logs:

1. Ensure the test suite has completed successfully
2. Check that log files exist in `/tmp/`
3. Verify log files contain relevant entries (grep for "Unified-Identity" or component-specific keywords)
4. Run the visualization script manually to see any error messages:
   ```bash
   python3 generate_workflow_ui.py
   ```

