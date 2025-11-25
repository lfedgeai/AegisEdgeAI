# SVID Renewal Demo Guide

This guide provides the best way to demonstrate automatic SVID renewal with renewal blips.

## Demo Setup

### Prerequisites
- All components built and ready
- `spiffe` Python library installed: `pip install spiffe`
- Terminal with multiple panes/windows (recommended: 4 panes)

### Quick Start

```bash
# Set renewal interval to 30 seconds for visible renewals
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
export UNIFIED_IDENTITY_ENABLED=true

# Run the test
./test_complete.sh --test-renewal --no-pause
```

## Best Demo Approach: 4-Pane Terminal Layout

### Terminal Layout

```
┌─────────────────────┬─────────────────────┐
│   Pane 1: Test      │   Pane 2: Agent Log │
│   (Main Control)    │   (Renewal Events)  │
├─────────────────────┼─────────────────────┤
│   Pane 3: Server    │   Pane 4: Client    │
│   Workload Log      │   Workload Log       │
│   (Server Renewals) │   (Client Renewals)  │
└─────────────────────┴─────────────────────┘
```

### Setup Commands

**Pane 1 (Main Control):**
```bash
cd /home/mw/AegisEdgeAI/hybrid-cloud-poc
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
export UNIFIED_IDENTITY_ENABLED=true
./test_complete.sh --test-renewal --no-pause
```

**Pane 2 (SPIRE Agent Log):**
```bash
tail -f /tmp/spire-agent.log | grep -E "renew|Renew|SVID|Unified-Identity.*Agent"
```

**Pane 3 (Server Workload Log):**
```bash
tail -f /tmp/mtls-server-app.log | grep -E "renew|Renew|SVID|BLIP|Message"
```

**Pane 4 (Client Workload Log):**
```bash
tail -f /tmp/mtls-client-app.log | grep -E "renew|Renew|SVID|BLIP|reconnect|Message"
```

## Demo Flow

### Phase 1: Setup (2-3 minutes)
1. **Start the test** in Pane 1
2. **Wait for components to start** - watch Pane 1 for:
   - ✓ SPIRE Server is running
   - ✓ SPIRE Agent is running
   - ✓ All components ready

### Phase 2: Agent SVID Renewal (Step 14)
**What to show:**
- **Pane 1**: Test progress showing "Agent SVID renewal detected!"
- **Pane 2**: Agent log showing renewal events:
  ```
  Unified-Identity: Agent Unified SVID renewed
  serial_number=...
  not_after=...
  ```

**Key Points:**
- "Agent SVID renews every ~30 seconds"
- "This is the foundation - when agent renews, workloads automatically renew"
- "Notice the serial number changes with each renewal"

**Timing:** Wait for 2-3 renewals (60-90 seconds)

### Phase 3: Workload SVID Renewal (Step 15)
**What to show:**
- **Pane 1**: Python apps starting
- **Pane 3**: Server log showing:
  ```
  Got initial SVID: spiffe://example.org/mtls-server
  Initial Certificate Serial: ...
  ```
- **Pane 4**: Client log showing similar

**Key Points:**
- "Python apps connect to SPIRE Agent and get SVIDs"
- "They automatically monitor for renewals"
- "When agent SVID renews, workload SVIDs renew too"

### Phase 4: Communication & Renewal Blips
**What to show:**
- **Pane 3 & 4**: Messages being sent/received
- **Pane 3**: Server renewal events:
  ```
  ╔════════════════════════════════════════════════════════════════╗
  ║  🔄 SVID RENEWAL DETECTED - RENEWAL BLIP EVENT                  ║
  ╚════════════════════════════════════════════════════════════════╝
  Old Certificate Serial: ...
  New Certificate Serial: ...
  ⚠️  RENEWAL BLIP: Existing connections may experience brief interruption
  ```
- **Pane 4**: Client reconnection:
  ```
  SVID renewed! Reconnecting...
  Connection error (renewal blip) - reconnecting...
  ✓ Reconnected successfully
  ```

**Key Points:**
- "Watch for the renewal blip - connection briefly interrupted"
- "Apps automatically detect renewal and reconnect"
- "This is the 'blip' - minimal disruption, automatic recovery"
- "New connections use the renewed certificate immediately"

**Timing:** Let it run for 2-3 renewal cycles (60-90 seconds)

## Key Demo Points

### 1. Automatic Renewal Chain
```
Agent SVID Renews (every ~30s)
    ↓
Workload SVIDs Automatically Renew
    ↓
Apps Detect Renewal
    ↓
Brief Connection Blip
    ↓
Automatic Reconnection
```

### 2. What Makes This Special
- **Automatic**: No manual intervention needed
- **Cascading**: Agent renewal triggers workload renewal
- **Resilient**: Apps handle blips automatically
- **Visible**: Renewal blips are logged for demonstration

### 3. Real-World Impact
- **Security**: Certificates rotate frequently (30s vs 24h default)
- **Availability**: Minimal disruption (brief blip, auto-recovery)
- **Observability**: All renewals logged and visible

## Alternative: Single Terminal Demo

If you only have one terminal:

```bash
# Terminal 1: Run test
export SPIRE_AGENT_SVID_RENEWAL_INTERVAL=30
export UNIFIED_IDENTITY_ENABLED=true
./test_complete.sh --test-renewal --no-pause

# In another terminal (or after test starts):
# Watch all 3 logs together
tail -f /tmp/spire-agent.log /tmp/mtls-server-app.log /tmp/mtls-client-app.log | grep -E "renew|Renew|SVID|BLIP|reconnect"
```

## What to Highlight

### Before Demo
- "We've configured agent SVID renewal to 30 seconds (normally 24 hours)"
- "This makes renewals visible for demonstration"
- "In production, you'd use longer intervals"

### During Demo
- **Agent Renewal**: "See the agent SVID renewing every 30 seconds"
- **Workload Renewal**: "Workloads automatically renew when agent renews"
- **Blip**: "Watch for the brief connection interruption - this is the renewal blip"
- **Recovery**: "Apps automatically reconnect - no manual intervention"

### After Demo
- "All renewals are automatic and logged"
- "The blip is minimal - just a brief reconnection"
- "This demonstrates the full end-to-end renewal flow"

## Troubleshooting

### If renewals aren't visible:
1. Check `agent_ttl` in server config (should be 60s)
2. Check `availability_target` in agent config (should be 30s)
3. Verify Unified-Identity feature flag is enabled
4. Check logs for errors

### If Python apps don't start:
1. Verify `spiffe` library: `pip install spiffe`
2. Check registration entries exist
3. Verify SPIRE Agent socket exists: `/tmp/spire-agent/public/api.sock`

### If blips aren't visible:
1. Apps may reconnect too quickly
2. Check logs for "RENEWAL BLIP" or "reconnect" messages
3. Look for connection errors followed by successful reconnection

## Demo Checklist

- [ ] All components running
- [ ] Agent SVID renewals visible (every ~30s)
- [ ] Python apps started and communicating
- [ ] Workload SVID renewals visible
- [ ] Renewal blips visible in logs
- [ ] Apps automatically reconnecting
- [ ] All 3 log files showing activity

## Summary

**Best Demo Approach:**
1. Use 4-pane terminal layout
2. Show agent renewal first (Step 14)
3. Show workload renewal and blips (Step 15)
4. Highlight the automatic nature and minimal disruption
5. Point out the full renewal chain: Agent → Workload → mTLS

**Key Message:**
"Automatic SVID renewal with minimal disruption - the renewal blip is brief and handled automatically, demonstrating resilient certificate rotation in action."

