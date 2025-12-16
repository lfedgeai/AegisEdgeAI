# Files to Copy to Remote Machine

Copy these 4 files to your remote machine at: `~/dhanush/hybrid-cloud-poc-backup/`

---

## 📁 File 1: `fix-tpm-plugin-communication.sh`

**Purpose:** Diagnoses and identifies TPM Plugin communication issues

**Location:** Already created in your editor

**How to copy:**
1. Open `fix-tpm-plugin-communication.sh` in your editor
2. Copy entire content
3. On remote machine:
   ```bash
   cd ~/dhanush/hybrid-cloud-poc-backup
   nano fix-tpm-plugin-communication.sh
   # Paste content, Ctrl+X, Y, Enter
   chmod +x fix-tpm-plugin-communication.sh
   ```

---

## 📁 File 2: `configure-single-machine.sh`

**Purpose:** Configures the system to run on a single machine

**Location:** Already created in your editor

**How to copy:**
1. Open `configure-single-machine.sh` in your editor
2. Copy entire content
3. On remote machine:
   ```bash
   cd ~/dhanush/hybrid-cloud-poc-backup
   nano configure-single-machine.sh
   # Paste content, Ctrl+X, Y, Enter
   chmod +x configure-single-machine.sh
   ```

---

## 📁 File 3: `quick-fix-and-test.sh`

**Purpose:** Automated fix and test script (combines diagnosis + fix + test)

**Location:** Already created in your editor

**How to copy:**
1. Open `quick-fix-and-test.sh` in your editor
2. Copy entire content
3. On remote machine:
   ```bash
   cd ~/dhanush/hybrid-cloud-poc-backup
   nano quick-fix-and-test.sh
   # Paste content, Ctrl+X, Y, Enter
   chmod +x quick-fix-and-test.sh
   ```

---

## 📁 File 4: `SINGLE_MACHINE_SETUP_GUIDE.md`

**Purpose:** Complete step-by-step instructions

**Location:** Already created in your editor

**How to copy:**
1. Open `SINGLE_MACHINE_SETUP_GUIDE.md` in your editor
2. Copy entire content
3. On remote machine:
   ```bash
   cd ~/dhanush/hybrid-cloud-poc-backup
   nano SINGLE_MACHINE_SETUP_GUIDE.md
   # Paste content, Ctrl+X, Y, Enter
   ```

---

## 🚀 Quick Start (After Copying Files)

### Option A: Automated Fix (Recommended)

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Run the automated fix and test
./quick-fix-and-test.sh
```

This will:
1. Diagnose current issues
2. Fix TPM Plugin communication
3. Restart SPIRE Agent with correct environment
4. Test Workload SVID generation
5. Show summary

### Option B: Manual Step-by-Step

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Step 1: Diagnose
./fix-tpm-plugin-communication.sh

# Step 2: Fix based on diagnostic output
# (Follow recommendations from diagnostic)

# Step 3: Configure single machine
./configure-single-machine.sh

# Step 4: Test
./test_complete.sh --no-pause
```

### Option C: Follow Complete Guide

```bash
cd ~/dhanush/hybrid-cloud-poc-backup

# Read the guide
cat SINGLE_MACHINE_SETUP_GUIDE.md

# Follow Phase 1, 2, and 3 step-by-step
```

---

## 📊 Expected Results

After running the scripts, you should have:

✅ **No more "stub data" errors**
- SPIRE Agent uses real TPM data
- TPM Plugin communication working

✅ **Workload API socket created**
- `/tmp/spire-agent/public/api.sock` exists
- Applications can fetch SVIDs

✅ **Successful attestation**
- Keylime Verifier accepts attestation
- SPIRE Server issues Agent SVID

✅ **Single machine configuration**
- All services on same machine
- No SSH errors

---

## 🔍 Troubleshooting

If scripts fail, check:

```bash
# Check all services
ps aux | grep -E "spire-server|spire-agent|keylime|tpm_plugin"

# Check all logs
tail -50 /tmp/spire-agent.log
tail -50 /tmp/tpm-plugin-server.log
tail -50 /tmp/spire-server.log
tail -50 /tmp/keylime-verifier.log

# Check sockets
ls -la /tmp/spire-agent/public/api.sock
ls -la /tmp/spire-data/tpm-plugin/tpm-plugin.sock
```

---

## 📞 Need Help?

1. Run diagnostic: `./fix-tpm-plugin-communication.sh`
2. Check the guide: `cat SINGLE_MACHINE_SETUP_GUIDE.md`
3. Look for specific error in logs
4. Search for error pattern in guide

---

## 🎯 Next Steps After Success

1. ✅ Verify end-to-end flow works
2. ✅ Run integration test: `./test_complete_integration.sh --no-pause`
3. ✅ Build CI/CD automation
4. ✅ Integrate Keylime optimization
5. ✅ Test Kubernetes integration

Good luck! 🚀
