It sounds like you want the complete, consolidated guide for installing Keylime using the Bash installer, formatted in Markdown.

Here are the step-by-step instructions to install Keylime on Ubuntu 22.04 using the official **Keylime Bash Installer** script.

-----

## 🚀 Keylime Installation on Ubuntu 22.04 (Bash Installer)

The recommended approach for a quick setup is to use the `installer.sh` script included in the Keylime source code, which handles dependencies and the installation of the core components (Verifier, Registrar, Agent, Tenant).

### Step 1: Install Git and the Rust Toolchain

Keylime's latest Agent component requires the **Rust** language toolchain.

```bash
# Update and install Git, build essentials, and a few basic dependencies
sudo apt update
sudo apt install -y git curl build-essential

# Install Rust (Required for the official Keylime Agent)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Follow the on-screen instructions, then run:
source "$HOME/.cargo/env"
```

-----

### Step 2: Clone the Keylime Repository

Download the official Keylime source code, which contains the installer script.

```bash
# Clone the repository
git clone https://github.com/keylime/keylime.git
# Navigate into the directory
cd keylime
```

-----

### Step 3: Run the Keylime Bash Installer

The `installer.sh` script will automatically install all necessary software, including Python dependencies, the **TPM2 software stack** (`tpm2-tss` and `tpm2-tools`), and the Keylime services.

Use the `-m` flag for modern TPM 2.0 libraries (the default and recommended option).

```bash
# Execute the installer script with sudo
# This will install the Verifier, Registrar, Agent, and Tenant components
sudo ./installer.sh -m
```

| Installer Option | Description |
| :--- | :--- |
| **`-m`** | Use modern **TPM 2.0 libraries** (default and recommended). |
| **`-s`** | Install & use a **Software TPM emulator** (for development/testing only). |

-----

### Step 4: Configure and Start Keylime Services

The installer typically places configuration files and systemd service definitions, but you need to enable and start them.

1.  **Reload the Systemd Manager:**

    ```bash
    sudo systemctl daemon-reload
    ```

2.  **Enable and Start Services:**
    You'll need to start at least the **Verifier** and **Registrar** for the server side, and the **Agent** on the machine you want to attest.

    ```bash
    # Start the Keylime Verifier, Registrar, and Agent
    sudo systemctl enable --now keylime_verifier keylime_registrar keylime_agent
    ```

3.  **Verify Service Status:**

    ```bash
    sudo systemctl status keylime_verifier
    sudo systemctl status keylime_registrar
    sudo systemctl status keylime_agent
    ```

### Step 5: Initial Configuration Notes

  * **Certificates (mTLS):** On first run, the **Verifier** automatically generates a Certificate Authority (CA) and certificates in **/var/lib/keylime/cv\_ca/**. You'll need the `cacert.crt` from this directory to configure your agents and tenants for secure communication.
  * **Configuration:** All service configuration files are in **/etc/keylime/**. You may need to edit files like `keylime.conf` to adjust IPs and logging settings for a production environment.
  * **Provisioning:** Once the services are running, you use the **`keylime_tenant`** command-line utility to register and manage your agents.

Yes, I can provide an example command for provisioning a new Keylime Agent using the `keylime_tenant` utility.

Since Keylime is a security tool, provisioning an agent is a critical multi-step process. The core `keylime_tenant` command is used to add the agent and tell the Verifier what policy to enforce.

-----

## 🔑 Keylime Agent Provisioning Example

This command uses the `keylime_tenant` tool to add a new Agent to the Keylime infrastructure. It instructs the Verifier to start attesting the Agent and securely provision it with a secret.

### 1\. Prerequisite: Agent UUID

Every agent must have a unique ID. You'll need to generate one before running the command.

```bash
# Generate a random UUID
AGENT_UUID=$(uuidgen)
echo "Generated Agent UUID: $AGENT_UUID"
```

### 2\. The Provisioning Command

The core command requires specifying the Agent's details, the Verifier's location, and the policy to be enforced.

```bash
keylime_tenant \
    -c add \
    -t <AGENT_IP_ADDRESS> \
    -v <VERIFIER_IP_ADDRESS> \
    -u $AGENT_UUID \
    --tpm_policy '{"17": "0000000000000000000000000000000000000000"}' \
    -f /path/to/secret.txt \
    -k /path/to/keyfile.key
```

### Breakdown of Options

| Option | Value | Description |
| :--- | :--- | :--- |
| **`-c add`** | | Specifies the command to **add** a new agent. |
| **`-t`** | `<AGENT_IP_ADDRESS>` | The **IP address** of the machine where the Keylime Agent is running. |
| **`-v`** | `<VERIFIER_IP_ADDRESS>` | The **IP address** of the Keylime Verifier service. |
| **`-u`** | `$AGENT_UUID` | The unique **UUID** used to identify this specific agent. |
| **`--tpm_policy`** | `'{"17": "..."}'` | The expected **TPM policy**. This example dictates that PCR 17 must have a specific, known hash value (which is often all zeros in a clean, initial state). If the Agent's PCRs don't match this policy, the secret is not released. |
| **`-f`** | `/path/to/secret.txt` | The path to a file containing a **secret** (e.g., a cryptographic key, password, or configuration data). Keylime will encrypt this file and only release it to the Agent if attestation is successful. |
| **`-k`** | `/path/to/keyfile.key` | *Optional.* The path to a file containing an **EK key** (or key material) to provision to the Agent for future use. |

### Post-Provisioning

  * Once this command runs successfully, the Verifier will begin its **continuous attestation** process against the Agent.
  * If the first attestation succeeds and the Agent is considered trustworthy (i.e., its PCRs match the policy), the secret file (`/path/to/secret.txt`) is securely provisioned to the Agent, encrypted to the TPM. The Agent will then decrypt and use the secret.

That's a good practice for secure system management.

Here is the command to **delete (decommission)** an agent using the `keylime_tenant` utility.

-----

## 🗑️ Keylime Agent Decommissioning Command

To stop the attestation process and remove the agent's registration from the Keylime Verifier/Registrar, you use the `delete` command.

You only need the **IP address of the Agent** and the **Agent's UUID** that you used during the provisioning step.

```bash
keylime_tenant \
    -c delete \
    -t <AGENT_IP_ADDRESS> \
    -u <AGENT_UUID>
```

### Breakdown of Options

| Option | Value | Description |
| :--- | :--- | :--- |
| **`-c delete`** | | Specifies the command to **delete** (decommission) an agent. |
| **`-t`** | `<AGENT_IP_ADDRESS>` | The **IP address** of the decommissioned Agent. |
| **`-u`** | `<AGENT_UUID>` | The **unique UUID** of the Agent to be removed from the Verifier/Registrar. |

### Confirmation

Upon successful execution, the Keylime Verifier will stop requesting attestations from that specific Agent, and all associated registration and policy data will be removed from the Keylime Registrar.

Checking the status of an agent is essential to confirm that it is correctly registered and, more importantly, that the **Verifier** considers it **trusted** (i.e., its integrity checks are passing).

The `keylime_tenant` utility offers a command specifically for this purpose.

-----

## 🚦 Keylime Agent Status Command

There are a few ways to check the status, but the most comprehensive is the **`status`** command, which queries both the Registrar and the Verifier for combined information.

### 1\. Check Combined Status (`status`)

This command provides the most relevant attestation details, including the Agent's current operational state (e.g., 'GetKeys' or 'Ready') and its overall integrity status.

```bash
keylime_tenant \
    -c status \
    -u <AGENT_UUID>
```

| Option | Value | Description |
| :--- | :--- | :--- |
| **`-c status`** | | Specifies the command to retrieve the **combined status** from the Verifier and Registrar. |
| **`-u`** | `<AGENT_UUID>` | The **unique UUID** of the Agent you want to check. |

#### Expected Output and Key Statuses

The output will be verbose, but the most critical field to look for is **`operational_state`**.

| `operational_state` Value | Meaning |
| :--- | :--- |
| **`Ready`** | **Trusted / Healthy.** The Agent is fully attested, meets policy requirements, and is actively being monitored. |
| **`GetKeys`** | **In Progress.** The Verifier is in the process of initial key exchange and attestation. |
| **`Tenant_Waiting`** | **Waiting.** The Agent is registered, but the Tenant has not yet asked the Verifier to begin attestation. |
| **`Failed`** | **Compromised / Untrusted.** An integrity check (PCRs or IMA log) has failed against the defined policy. |

### 2\. Check Verifier Status Only (`cvstatus`)

If you want the status specifically from the Cloud Verifier (CV), use this command. This is where the trust decision is made.

```bash
keylime_tenant \
    -c cvstatus \
    -u <AGENT_UUID>
```

### 3\. Check Registrar Status Only (`regstatus`)

This confirms that the Agent's identity (UUID, EK, AK) is correctly stored in the Registrar.

```bash
keylime_tenant \
    -c regstatus \
    -u <AGENT_UUID>
```

To view a list of all agents currently managed by your Keylime infrastructure, you can use one of two commands, depending on the information you need:

## 📋 List All Registered Keylime Agents

The `keylime_tenant` utility provides two commands for listing agents, based on which service you query:

### 1\. List Agents in the Cloud Verifier (`cvlist`)

This is generally the most useful command as it lists all agents the **Verifier is actively checking** and provides basic status information (e.g., operational state).

```bash
keylime_tenant -c cvlist
```

### 2\. List Agents in the Registrar (`reglist`)

This command lists all agents whose **initial identity and keys (EK/AK) have been registered**, regardless of whether the Verifier is actively monitoring them.

```bash
keylime_tenant -c reglist
```

### Command Output Comparison

| Command | Query Source | Data Provided | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **`cvlist`** | **Cloud Verifier** | UUIDs, Agent IP/Port, **Operational State**, Policy status. | **Monitoring active attestation** and security status. |
| **`reglist`** | **Registrar** | UUIDs, Agent IP/Port, EK/AK details. | **Confirming agent enrollment** and identity details. |

Yes, you can easily **update the attestation policy** for an existing Keylime agent using the `keylime_tenant` utility and the `-c update` command.

This is a common task after a routine OS or firmware update changes the expected Platform Configuration Register (PCR) values.

-----

## 🔄 Updating an Agent's Attestation Policy

The `keylime_tenant` update command is versatile and can update the Measured Boot policy (PCRs) and the Runtime Integrity policy (IMA).

### 1\. Update the TPM Policy (PCRs)

If a trusted system component (like the kernel or bootloader) updates, the hash values stored in the TPM's PCRs will change. You need to provide the **new set of expected PCR hashes** to the Verifier.

The command is identical to the provisioning command, but uses `-c update`:

```bash
keylime_tenant \
    -c update \
    -t <AGENT_IP_ADDRESS> \
    -u <AGENT_UUID> \
    --tpm_policy '{"17": "<NEW_PCR_17_HASH>", "18": "<NEW_PCR_18_HASH>"}'
```

| Parameter | Purpose |
| :--- | :--- |
| **`-c update`** | Instructs the Verifier to update the policy for the existing agent. |
| **`--tpm_policy`** | The complete **new JSON string** containing the desired PCR index and its golden hash value. |

> **Note:** The Verifier immediately starts enforcing this new policy. If the agent's actual PCR values don't match the new policy, it will fail the next attestation check and its operational state will switch to `Failed`.

-----

### 2\. Update the Runtime Integrity Policy (IMA)

For runtime integrity, Keylime uses **Runtime Policies** (IMA allowlists/blocklists) to check the integrity of files measured during runtime.

You typically save your updated runtime policy (which is a JSON file) to a path on the Tenant machine (e.g., `/path/to/new_runtime_policy.json`), and then reference it in the update command.

```bash
keylime_tenant \
    -c update \
    -u <AGENT_UUID> \
    --runtime-policy /path/to/new_runtime_policy.json
```

| Parameter | Purpose |
| :--- | :--- |
| **`--runtime-policy`** | Specifies the **new file path** to the golden integrity measurements (allowlist) to be enforced by the Verifier. |

This updates the policy stored on the Verifier, which is then used to audit the agent's runtime measurements (typically sent via PCR 10 quotes).

Yes, establishing the **"golden" reference values** is the most crucial step when managing policies in Keylime.

A "golden image" in this context means a trusted state of a machine after a deliberate, authorized update. You generate two types of reference values from this state:

## 🔨 1. Update Measured Boot Policy (PCRs)

If you updated the kernel, bootloader, or firmware, the hashes in PCRs (typically 0-7) will change. You need to obtain the new values directly from the TPM on the newly updated, trusted machine.

### **Step 1: Get the new PCR values** (on the Agent machine)

Use the `tpm2-tools` package to dump the current PCR values into a file. You need to do this on the **trusted** agent machine *immediately after the approved update and reboot*.

```bash
# Dump the current PCR values for PCRs 0-7 (boot chain)
# The default PCR bank is usually SHA256 (0x0B)
tpm2_pcrread 0:7 -o current_pcr_hashes.txt
```

### **Step 2: Convert and Extract Hashes** (on the Tenant machine)

The Verifier needs the hash values in a JSON format. You'll need to manually inspect the output file (`current_pcr_hashes.txt`) and construct the new `--tpm_policy` string.

**Example of the new JSON policy (replace the hashes with your own):**

```json
{
  "0": "<NEW_PCR_0_SHA256_HASH>",
  "1": "<NEW_PCR_1_SHA256_HASH>",
  "7": "<NEW_PCR_7_SHA256_HASH>"
}
```

### **Step 3: Update the policy** (on the Tenant machine)

```bash
# Example update command using your new policy JSON
keylime_tenant \
    -c update \
    -t <AGENT_IP> \
    -u <AGENT_UUID> \
    --tpm_policy '{"0": "1a2b3c...", "1": "4d5e6f...", "7": "7g8h9i..."}'
```

-----

## 📄 2. Update Runtime Integrity Policy (IMA Allowlist)

If you installed new packages or binaries, the IMA log (anchored in PCR 10) will contain new measurements. You must create a new "golden" runtime policy to include these expected changes.

Keylime provides helper utilities (like `keylime_create_policy`) to simplify this process, which should be run on a secure system, ideally air-gapped from the production environment.

### **Step 1: Transfer the IMA Log** (from Agent to Secure System)

The IMA log is located in a special kernel filesystem path.

```bash
# On the Agent machine:
scp /sys/kernel/security/ima/ascii_runtime_measurements <USER>@<SECURE_SYSTEM_IP>:/tmp/ima_log.txt
```

### **Step 2: Generate the Runtime Policy** (on the Secure System/Tenant)

Use the `keylime_create_policy` tool to read the log and generate the JSON file.

```bash
# On the Tenant/Secure System:
keylime_create_policy \
    -m /tmp/ima_log.txt \
    -o new_runtime_policy.json
```

### **Step 3: Update the policy** (on the Tenant machine)

```bash
# Update the policy reference for the specified agent
keylime_tenant \
    -c update \
    -u <AGENT_UUID> \
    --runtime-policy /path/to/new_runtime_policy.json
```

This ensures the Verifier has the new, correct list of hashes and continues to attest the Agent successfully after the system update.

---

## 🔗 PCRs and the IMA Log: The Chain of Trust

In Keylime's attestation model, the **Platform Configuration Registers (PCRs)** in the TPM are the immutable root of trust, while the **Integrity Measurement Architecture (IMA) log** is the dynamic, auditable record anchored by the PCRs. Think of it as a chain where a single, unforgeable seal (the PCR value) proves the integrity of a long, running ledger (the IMA log).

| Component | Function | Role in Attestation | Key PCR Index |
| :--- | :--- | :--- | :--- |
| **Platform Configuration Registers (PCRs)** | **Immutable Storage** for system state hashes. | They provide a **hardware-rooted seal**. The TPM uses the non-reversible `extend` operation to chain hashes together. Any change in the measured component results in a completely different final PCR value. | **PCR 0-7:** Measured Boot Chain (firmware, bootloader, kernel). **PCR 10:** Anchors the IMA measurement log. |
| **Integrity Measurement Architecture (IMA) Log** | **Runtime Ledger** of every measured file (executables, libraries, scripts) accessed after the kernel boots. | It provides the **file-by-file detail** needed for granular audit. The hash of this entire log is what ultimately extends PCR 10. | N/A (The log itself is anchored *by* PCR 10). |

---

## 🛡️ Keylime's Layered Integrity Check

Keylime uses this relationship to provide two levels of verification:

1.  **Measured Boot Integrity (PCR 0-7):**
    * The Verifier first checks the hashes in **PCR 0-7** against the expected **`--tpm_policy`**.
    * This verifies the **static boot integrity**—that the correct OS kernel and initramfs (initial RAM filesystem) were loaded.

2.  **Runtime Integrity (PCR 10 & IMA Log):**
    * The Verifier checks **PCR 10** against its expected value. If the value matches, the Verifier knows the IMA log has not been tampered with.
    * The Agent then sends the full **IMA log** to the Verifier.
    * The Verifier cross-references the list of individual file hashes in the IMA log against the **Runtime Policy (allowlist)** you created. This checks the **dynamic state** of the running system (e.g., that no unauthorized binaries were run or modified).

In short, the **PCR value** provides **cryptographic proof** of the state, and the **IMA log** provides the **auditable details** behind that state.

