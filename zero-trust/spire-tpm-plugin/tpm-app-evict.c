// tpm-app-evict.c
#include <stdio.h>
#include <stdlib.h>
#include <tss2/tss2_esys.h>
#include <tss2/tss2_tctildr.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <persistent-handle-hex>\n", argv[0]);
        fprintf(stderr, "Example: %s 0x8101000B\n", argv[0]);
        return 1;
    }

    TPMI_DH_PERSISTENT handle = 0;
    if (sscanf(argv[1], "%x", &handle) != 1) {
        fprintf(stderr, "[ERROR] Invalid handle format: %s\n", argv[1]);
        return 1;
    }

    ESYS_CONTEXT *ctx = NULL;
    TSS2_TCTI_CONTEXT *tcti = NULL;
    TSS2_RC rc;

    const char *tcti_conf = getenv("TCTI");
    if (!tcti_conf) tcti_conf = "swtpm:host=127.0.0.1,port=2321";

    rc = Tss2_TctiLdr_Initialize(tcti_conf, &tcti);
    if (rc != TSS2_RC_SUCCESS) { fprintf(stderr, "Tcti init failed\n"); return 1; }
    rc = Esys_Initialize(&ctx, tcti, NULL);
    if (rc != TSS2_RC_SUCCESS) { fprintf(stderr, "Esys init failed\n"); return 1; }

    // Query persistent handles
    TPMS_CAPABILITY_DATA *cap = NULL;
    rc = Esys_GetCapability(ctx,
                            ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                            TPM2_CAP_HANDLES,
                            TPM2_PERSISTENT_FIRST,
                            TPM2_MAX_CAP_HANDLES,
                            NULL,
                            &cap);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "GetCapability failed rc=0x%08x\n", rc);
        goto out;
    }

    int found = 0;
    for (UINT32 i = 0; i < cap->data.handles.count; i++) {
        if (cap->data.handles.handle[i] == handle) {
            found = 1;
            break;
        }
    }
    Esys_Free(cap);

    if (!found) {
        printf("[INFO] Handle 0x%08x not present, nothing to evict\n", handle);
        goto out;
    }

    // Load handle into ESYS_TR
    ESYS_TR key_tr = ESYS_TR_NONE;
    rc = Esys_TR_FromTPMPublic(ctx, handle,
                               ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                               &key_tr);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "TR_FromTPMPublic failed rc=0x%08x\n", rc);
        goto out;
    }

    // Empty owner auth
    TPM2B_AUTH emptyAuth = { .size = 0 };
    Esys_TR_SetAuth(ctx, ESYS_TR_RH_OWNER, &emptyAuth);

    // Evict
    ESYS_TR new_tr = ESYS_TR_NONE;
    rc = Esys_EvictControl(ctx,
                           ESYS_TR_RH_OWNER, key_tr,
                           ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
                           handle, &new_tr);
    if (rc == TSS2_RC_SUCCESS) {
        printf("[SUCCESS] Evicted handle 0x%08x\n", handle);
    } else {
        fprintf(stderr, "[ERROR] EvictControl rc=0x%08x\n", rc);
    }

    // Clean up only if still valid
    if (new_tr != ESYS_TR_NONE) {
        Esys_TR_Close(ctx, &new_tr);
    }
    if (key_tr != ESYS_TR_NONE) {
        Esys_TR_Close(ctx, &key_tr);
    }

out:
    Esys_Finalize(&ctx);
    Tss2_TctiLdr_Finalize(&tcti);
    return 0;
}

