# Security Fix Options for Issues #143 and #164

This document outlines comprehensive options to address the security issues identified in:
- [Issue #164](https://github.com/lfedgeai/AegisEdgeAI/issues/164): Hardcoded CAMARA Credentials in Test Scripts
- [Issue #143](https://github.com/lfedgeai/AegisEdgeAI/issues/143): CAMARA Token Storage Security

---

## Issue #164: Hardcoded CAMARA Credentials

### Problem
Hardcoded `CAMARA_BASIC_AUTH` credentials in:
- `enterprise-private-cloud/test_onprem.sh` (line 552)
- `test_complete_control_plane.sh` (line 219)

### Fix Options

#### Option 1: Remove Hardcoded Values, Require Environment Variable (Recommended)
**Approach**: Remove all hardcoded credentials and require `CAMARA_BASIC_AUTH` to be set via environment variable.

**Pros:**
- ✅ No credentials in repository
- ✅ Simple implementation
- ✅ Clear error messages guide users
- ✅ Works with CI/CD secret management

**Cons:**
- ⚠️ Requires users to set environment variable
- ⚠️ May break existing automated scripts

**Implementation:**
```bash
# In test_onprem.sh and test_complete_control_plane.sh
if [ "$CAMARA_BYPASS" != "true" ] && [ -z "${CAMARA_BASIC_AUTH:-}" ]; then
    echo "ERROR: CAMARA_BASIC_AUTH is required when CAMARA_BYPASS=false"
    echo "Set it with: export CAMARA_BASIC_AUTH='Basic <base64_encoded>'"
    exit 1
fi
```

---

#### Option 2: Use Configuration File (Not in Git)
**Approach**: Read credentials from a local config file that's gitignored.

**Pros:**
- ✅ Credentials not in repository
- ✅ Easy for local development
- ✅ Can provide `.env.example` template

**Cons:**
- ⚠️ File could be accidentally committed
- ⚠️ Requires additional file management

**Implementation:**
```bash
# Create .env.local (gitignored)
if [ -f ".env.local" ]; then
    source .env.local
fi
```

---

#### Option 3: Use Secret Management Service
**Approach**: Integrate with AWS Secrets Manager, HashiCorp Vault, or similar.

**Pros:**
- ✅ Enterprise-grade security
- ✅ Automatic rotation support
- ✅ Audit logging
- ✅ Fine-grained access control

**Cons:**
- ⚠️ Complex setup
- ⚠️ Requires infrastructure
- ⚠️ May be overkill for test scripts

**Implementation:**
```bash
# Example with AWS Secrets Manager
CAMARA_BASIC_AUTH=$(aws secretsmanager get-secret-value \
    --secret-id camara-credentials \
    --query SecretString --output text)
```

---

#### Option 4: Use Keyring/OS Credential Store
**Approach**: Store credentials in OS keyring (Linux keyring, macOS Keychain, Windows Credential Manager).

**Pros:**
- ✅ OS-level security
- ✅ Encrypted storage
- ✅ No files to manage

**Cons:**
- ⚠️ Platform-specific
- ⚠️ Requires additional dependencies
- ⚠️ May not work in all environments

**Implementation:**
```python
# Python keyring example
import keyring
CAMARA_BASIC_AUTH = keyring.get_password("camara", "basic_auth")
```

---

## Issue #143: CAMARA Token Storage Security

### Problem
- `auth_req_id` stored in plaintext file: `camara_auth_req_id.txt`
- File permissions `0o600` may not be sufficient
- No encryption at rest
- No token rotation policy

### Fix Options

#### Option 1: Encrypt File with Symmetric Encryption (Recommended for Quick Fix)
**Approach**: Encrypt `auth_req_id` using AES encryption with a key from environment variable.

**Pros:**
- ✅ Encrypted at rest
- ✅ Minimal code changes
- ✅ Works with existing file-based approach
- ✅ Can use environment variable for key

**Cons:**
- ⚠️ Key management still needed
- ⚠️ Key in environment variable (better than plaintext, but not ideal)

**Implementation:**
```python
from cryptography.fernet import Fernet
import base64
import os

def _get_encryption_key() -> bytes:
    """Get encryption key from environment variable."""
    key_str = os.getenv("CAMARA_ENCRYPTION_KEY")
    if not key_str:
        raise ValueError("CAMARA_ENCRYPTION_KEY environment variable required")
    # Generate key from string (or use directly if 32 bytes base64)
    return base64.urlsafe_b64encode(key_str.encode()[:32].ljust(32, b'0'))

def _save_auth_req_id_to_file(self, auth_req_id: str) -> None:
    """Save encrypted auth_req_id to file."""
    key = _get_encryption_key()
    fernet = Fernet(base64.urlsafe_b64encode(key))
    encrypted = fernet.encrypt(auth_req_id.encode())
    file_path.write_bytes(encrypted)
    file_path.chmod(0o600)
```

---

#### Option 2: Use OS Keyring (Recommended for Production)
**Approach**: Store `auth_req_id` in OS keyring instead of file.

**Pros:**
- ✅ OS-level encryption
- ✅ No file to manage
- ✅ Platform-native security
- ✅ Automatic key management

**Cons:**
- ⚠️ Requires `keyring` Python package
- ⚠️ Platform-specific behavior
- ⚠️ May need fallback for headless servers

**Implementation:**
```python
import keyring

def _save_auth_req_id(self, auth_req_id: str) -> None:
    """Save auth_req_id to OS keyring."""
    keyring.set_password("camara", "auth_req_id", auth_req_id)

def _load_auth_req_id(self) -> Optional[str]:
    """Load auth_req_id from OS keyring."""
    return keyring.get_password("camara", "auth_req_id")
```

---

#### Option 3: Use Secret Management Service
**Approach**: Store tokens in AWS Secrets Manager, HashiCorp Vault, etc.

**Pros:**
- ✅ Enterprise-grade security
- ✅ Built-in rotation
- ✅ Audit logging
- ✅ Centralized management

**Cons:**
- ⚠️ Requires infrastructure
- ⚠️ Additional dependencies
- ⚠️ Network dependency

**Implementation:**
```python
import boto3

def _save_auth_req_id(self, auth_req_id: str) -> None:
    """Save to AWS Secrets Manager."""
    client = boto3.client('secretsmanager')
    client.put_secret_value(
        SecretId='camara/auth_req_id',
        SecretString=auth_req_id
    )
```

---

#### Option 4: In-Memory Only with Environment Variable Fallback
**Approach**: Don't persist `auth_req_id`; use environment variable or re-fetch on startup.

**Pros:**
- ✅ No file storage
- ✅ Simple implementation
- ✅ No encryption needed

**Cons:**
- ⚠️ Requires re-authentication on restart
- ⚠️ May increase API calls
- ⚠️ Less convenient for long-running services

**Implementation:**
```python
def _load_auth_req_id(self) -> Optional[str]:
    """Load from environment or None (will fetch on demand)."""
    return os.getenv("CAMARA_AUTH_REQ_ID")

def _save_auth_req_id(self, auth_req_id: str) -> None:
    """Don't persist - just cache in memory."""
    self.auth_req_id = auth_req_id
    # Optionally log that it should be set as env var for next run
```

---

#### Option 5: Encrypted Database Storage
**Approach**: Store `auth_req_id` in encrypted SQLite database or add encrypted column.

**Pros:**
- ✅ Consistent with existing database approach
- ✅ Can reuse database encryption
- ✅ Single storage mechanism

**Cons:**
- ⚠️ Database encryption adds complexity
- ⚠️ Still need key management

---

## Recommended Combined Solution

### For Issue #164 (Hardcoded Credentials):
**Use Option 1**: Remove hardcoded values, require environment variable
- Quick to implement
- No infrastructure needed
- Clear security improvement

### For Issue #143 (Token Storage):
**Use Option 2**: OS Keyring with file fallback
- Best security for production
- Graceful degradation
- Platform-agnostic approach

### Implementation Priority:

1. **Immediate (High Priority)**:
   - Remove hardcoded credentials from test scripts
   - Add clear error messages
   - Update documentation

2. **Short-term (Medium Priority)**:
   - Implement OS keyring for `auth_req_id` storage
   - Add encryption key management
   - Add token rotation logic

3. **Long-term (Low Priority)**:
   - Consider secret management service integration
   - Add audit logging
   - Implement credential rotation automation

---

## Additional Security Recommendations

1. **Credential Rotation**:
   - Document rotation process
   - Add script to rotate credentials
   - Consider automatic rotation if using secret manager

2. **Audit Logging**:
   - Log when credentials are accessed
   - Log when tokens are refreshed
   - Monitor for suspicious activity

3. **Documentation**:
   - Update README with credential setup instructions
   - Add `.env.example` template
   - Document security best practices

4. **CI/CD Integration**:
   - Use GitHub Secrets for CI/CD
   - Never commit credentials
   - Validate no credentials in PRs

5. **Git History Cleanup** (if credentials are valid):
   - Consider using `git filter-branch` or BFG Repo-Cleaner
   - Rotate exposed credentials immediately
   - Document the cleanup process

---

## Testing Considerations

- Test with missing environment variables
- Test with invalid credentials
- Test keyring fallback mechanisms
- Test encryption/decryption
- Test token refresh scenarios
- Test in different environments (local, CI/CD, production)

