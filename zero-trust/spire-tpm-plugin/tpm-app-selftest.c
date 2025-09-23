#include <stdio.h>
#include <stdlib.h>
#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>

static ESYS_CONTEXT *esys_init(void) {
    ESYS_CONTEXT *ctx;
    TSS2_RC rc = Esys_Initialize(&ctx, NULL, NULL);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "[ERROR] Esys_Initialize rc=0x%08x\n", rc);
        return NULL;
    }
    return ctx;
}

static int load_context_file(const char *path, TPMS_CONTEXT *ctx_out) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        perror("[ERROR] fopen");
        return -1;
    }
    uint8_t buf[sizeof(TPMS_CONTEXT)];
    size_t len = fread(buf, 1, sizeof(buf), f);
    fclose(f);
    size_t offset = 0;
    TSS2_RC rc = Tss2_MU_TPMS_CONTEXT_Unmarshal(buf, len, &offset, ctx_out);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "[ERROR] Unmarshal rc=0x%08x\n", rc);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <context-file>\n", argv[0]);
        return 1;
    }

    ESYS_CONTEXT *ctx = esys_init();
    if (!ctx) return 1;

    TPMS_CONTEXT tpms_ctx;
    if (load_context_file(argv[1], &tpms_ctx) != 0) {
        Esys_Finalize(&ctx);
        return 1;
    }

    ESYS_TR handle;
    TSS2_RC rc = Esys_ContextLoad(ctx, &tpms_ctx, &handle);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "[ERROR] ContextLoad rc=0x%08x\n", rc);
        Esys_Finalize(&ctx);
        return 1;
    }

    TPM2B_PUBLIC *pub = NULL;
    rc = Esys_ReadPublic(ctx, handle,
                         ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                         &pub, NULL, NULL);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "[ERROR] ReadPublic rc=0x%08x\n", rc);
        Esys_FlushContext(ctx, handle);
        Esys_Finalize(&ctx);
        return 1;
    }

    printf("[OK] Context file %s loaded and public key read successfully\n", argv[1]);
    Esys_Free(pub);
    Esys_FlushContext(ctx, handle);
    Esys_Finalize(&ctx);
    return 0;
}

