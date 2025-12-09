# CAMARA Credentials Setup Guide

This guide explains how to set up CAMARA credentials to fix the security issue #164 (removing hardcoded credentials).

## Overview

The test scripts now read `CAMARA_BASIC_AUTH` from a file (`camara_basic_auth.txt`) instead of using hardcoded values. This follows the same pattern as `auth_req_id` storage.

## Priority Order

The scripts check for credentials in this order:
1. **Environment variable** `CAMARA_BASIC_AUTH` (highest priority)
2. **File** `camara_basic_auth.txt` (checked in multiple locations)
3. **Error** if `CAMARA_BYPASS=false` and no credentials found

## Setting Up Credentials File

### Step 1: Obtain CAMARA Credentials

1. Register at https://opengateway.telefonica.com/
2. Create an application to get `client_id` and `client_secret`
3. Generate Base64 encoded value:
   ```bash
   echo -n "client_id:client_secret" | base64
   ```

### Step 2: Create the Credentials File

Create a file named `camara_basic_auth.txt` in one of these locations (checked in order):

**For `test_onprem.sh`:**
- `mobile-sensor-microservice/camara_basic_auth.txt` (recommended)
- `camara_basic_auth.txt` (repo root)
- `/tmp/mobile-sensor-service/camara_basic_auth.txt`
- `camara_basic_auth.txt` (current directory)

**For `test_control_plane.sh`:**
- `mobile-sensor-microservice/camara_basic_auth.txt` (recommended)
- `camara_basic_auth.txt` (repo root)
- `mobile-sensor-service/camara_basic_auth.txt` (DB root directory)
- `camara_basic_auth.txt` (current directory)

### Step 3: Add Credentials to File

```bash
# Create the file with your credentials
echo "Basic <your_base64_encoded_credentials>" > mobile-sensor-microservice/camara_basic_auth.txt

# Set restrictive permissions (recommended)
chmod 600 mobile-sensor-microservice/camara_basic_auth.txt
```

**File Format:**
- Single line containing: `Basic <base64_encoded_value>`
- No quotes needed
- No trailing newline required (but OK if present)
- Example: `Basic NDcyOWY5ZDItMmVmNy00NTdhLWJlMzMtMGVkZjg4ZDkwZjA0OmU5N2M0Mzg0LTI4MDYtNDQ5YS1hYzc1LWUyZDJkNzNlOWQ0Ng==`

## Alternative: Environment Variable

You can also set it as an environment variable (takes precedence over file):

```bash
export CAMARA_BASIC_AUTH="Basic <your_base64_encoded_credentials>"
./test_onprem.sh
```

## Bypass Mode (No Credentials Needed)

If you don't need CAMARA API calls, you can use bypass mode:

```bash
export CAMARA_BYPASS="true"
./test_onprem.sh
```

## Verification

After setting up credentials, the script will show:
```
[OK] Loaded CAMARA_BASIC_AUTH from file: /path/to/camara_basic_auth.txt
```

If credentials are missing and bypass is disabled, you'll see:
```
[ERROR] CAMARA_BYPASS=false but CAMARA_BASIC_AUTH is not set
        CAMARA_BASIC_AUTH must be provided via one of:
        1. Environment variable: export CAMARA_BASIC_AUTH="Basic <base64(client_id:client_secret)>"
        2. File: Create camara_basic_auth.txt with the credentials
        ...
```

## Security Notes

⚠️ **Important Security Considerations:**

1. **File Permissions**: Set restrictive permissions on the credentials file:
   ```bash
   chmod 600 camara_basic_auth.txt
   ```

2. **Git**: The file `camara_basic_auth.txt` should NOT be committed to git. It contains sensitive credentials.

3. **File Location**: Store the file in a secure location accessible only to the service user.

4. **Credential Rotation**: If credentials are exposed, rotate them immediately and update the file.

## Troubleshooting

### File Not Found
- Check that the file exists in one of the checked locations
- Verify file permissions allow reading
- Check file path is correct

### Invalid Credentials
- Verify the format: must start with `Basic `
- Ensure Base64 encoding is correct
- Test credentials with curl (see mobile-sensor-microservice/README.md)

### Permission Denied
- Check file permissions: `ls -l camara_basic_auth.txt`
- Ensure script has read access
- Consider using environment variable instead

## Example Setup

```bash
# 1. Get your credentials from Telefonica Open Gateway
CLIENT_ID="your-client-id"
CLIENT_SECRET="your-client-secret"

# 2. Generate Base64 encoded value
BASIC_AUTH=$(echo -n "${CLIENT_ID}:${CLIENT_SECRET}" | base64)

# 3. Create credentials file
echo "Basic ${BASIC_AUTH}" > mobile-sensor-microservice/camara_basic_auth.txt

# 4. Set permissions
chmod 600 mobile-sensor-microservice/camara_basic_auth.txt

# 5. Verify
cat mobile-sensor-microservice/camara_basic_auth.txt

# 6. Run test script
cd enterprise-private-cloud
./test_onprem.sh
```

## Related Issues

- Issue #164: Security Issue: Hardcoded CAMARA Credentials in Test Scripts
- Issue #143: CAMARA Token Storage Security (auth_req_id storage)

## Test Files

Test scripts for verifying the credential loading logic are located in this directory:
- `test_camara_credentials.sh` - Basic verification tests
- `test_integration_scenarios.sh` - Integration tests

Run tests from this directory:
```bash
cd mobile-sensor-microservice
./test_camara_credentials.sh
./test_integration_scenarios.sh
```

