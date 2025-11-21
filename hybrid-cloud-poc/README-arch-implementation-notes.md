# Architecture Notes - TPM Quote Implementation

## TPM Quote Deadlock Resolution

### Problem
The `rust-keylime` agent experienced a deadlock when performing TPM quote operations on hardware TPMs. The issue occurred when:
1. The agent called `tpm2_quote` as a subprocess from within a TSS library context lock (`execute_with_nullauth_session`)
2. The subprocess tried to access the TPM through the resource manager (`/dev/tpmrm0`)
3. The TSS library was already holding a lock on the resource manager, causing a deadlock

### Solution

#### 1. Direct Device TCTI
**Implementation**: Use direct device TCTI (`/dev/tpm0`) instead of resource manager (`/dev/tpmrm0`) for the `tpm2_quote` subprocess.

**Location**: `code-rollout-phase-2/rust-keylime/keylime/src/tpm.rs` - `perform_quote_with_tpm2_command_using_context()`

**Details**:
- The TSS library uses the resource manager (`/dev/tpmrm0`) for its operations
- When calling `tpm2_quote` as a subprocess, we switch to the direct device (`/dev/tpm0`) to avoid conflicts
- This allows the subprocess to access the TPM without conflicting with the TSS library's resource manager connection
- The direct device provides direct access to the TPM hardware, bypassing the resource manager

**Code Reference**:
```rust
// Get TCTI from environment
// IMPORTANT: Use direct device (/dev/tpm0) instead of resource manager (/dev/tpmrm0)
// to avoid deadlock when called from within a TSS context lock.
// The TSS library uses the resource manager, so the subprocess should use the direct device.
let tcti = if std::env::var("TCTI").unwrap_or_default().contains("tpmrm0") {
    log::info!("Using direct device TCTI (device:/dev/tpm0) to avoid deadlock with TSS resource manager");
    "device:/dev/tpm0".to_string()
} else {
    std::env::var("TCTI").unwrap_or_else(|_| "device:/dev/tpm0".to_string())
};
```

#### 2. Parse PCR Data from tpm2_quote Output File
**Implementation**: Parse PCR data directly from the `tpm2_quote` output file instead of using the TSS library to read PCRs.

**Location**: `code-rollout-phase-2/rust-keylime/keylime/src/tpm.rs` - `perform_quote_with_tpm2_command_using_context()`

**Details**:
- The `tpm2_quote` command outputs PCR data in the `-o` file in a format that matches `pcrdata_to_vec()`
- Format: `TPML_PCR_SELECTION` (132 bytes) + `u32` (count) + `TPML_DIGEST[]` (532 bytes each)
- We parse this format directly using unsafe transmute to convert bytes to C structs
- This avoids calling the TSS library's `read_all()` function, which would try to acquire the same lock that's already held
- The parsed PCR data is then converted to `PcrData` for use by Keylime's quote verification

**Code Reference**:
```rust
// Parse PCR data from tpm2_quote output file to avoid deadlock with TSS context lock
// The -o file format matches pcrdata_to_vec: TPML_PCR_SELECTION + u32 (count) + TPML_DIGEST[]
// We parse this directly and convert to PcrData, which Keylime will then use
log::info!("Parsing PCR data from tpm2_quote output file...");
let quote_pcrs = fs::read(quote_pcrs_path)?;

// Skip TPML_PCR_SELECTION (we already have pcrlist)
pcr_bytes = &pcr_bytes[TPML_PCR_SELECTION_SIZE..];

// Parse count of TPML_DIGEST
let count = u32::from_le_bytes([pcr_bytes[0], pcr_bytes[1], pcr_bytes[2], pcr_bytes[3]]);
pcr_bytes = &pcr_bytes[4..];

// Parse TPML_DIGEST array using unsafe transmute (C structs from tss2_esys)
let mut digest_list = Vec::new();
for _ in 0..count {
    let digest: TPML_DIGEST = unsafe {
        std::ptr::read(pcr_bytes.as_ptr() as *const TPML_DIGEST)
    };
    digest_list.push(digest);
    pcr_bytes = &pcr_bytes[TPML_DIGEST_SIZE..];
}

// Convert to PcrData (newtype wrapper around Vec<TPML_DIGEST>)
let pcr_data: PcrData = unsafe {
    mem::transmute(digest_list)
};
```

### Benefits
1. **Eliminates Deadlock**: By using direct device TCTI and parsing PCRs from file, we avoid all TSS library lock conflicts
2. **Maintains Compatibility**: The PCR data format matches what Keylime expects, so verification works correctly
3. **Performance**: Direct device access can be faster than going through the resource manager for subprocess operations
4. **Reliability**: No dependency on TSS library state when reading PCRs, reducing potential failure points

### Trade-offs
1. **Unsafe Code**: Uses `unsafe` transmute to convert bytes to C structs, but this is safe because:
   - The structs are from `tss2_esys` (C bindings)
   - The memory layout is guaranteed by the C ABI
   - The format matches what `tpm2_quote` outputs
2. **Direct Device Access**: Requires appropriate permissions for `/dev/tpm0` (usually requires group membership or root)
3. **Format Dependency**: Relies on the specific format that `tpm2_quote` outputs, which could change in future versions

### Testing
- ✅ Verified with hardware TPM (quote operations complete successfully)
- ✅ Verified with software TPM (swtpm) - quote works correctly
- ✅ Manual `tpm2_quote` CLI tests confirm the format is correct
- ✅ Quote endpoint returns valid JSON with quote data

### Related Files
- `code-rollout-phase-2/rust-keylime/keylime/src/tpm.rs`: Main implementation
- `code-rollout-phase-3/start_agent_debug.sh`: Agent startup script with TPM setup
- `code-rollout-phase-3/cleanup.sh`: Cleanup script with TPM clear

### Environment Variables
- `USE_TPM2_QUOTE_DIRECT=1`: Enables the direct `tpm2_quote` subprocess approach
- `KEYLIME_AGENT_AK_CONTEXT`: Path to the AK context file (set automatically when using persistent AK)

