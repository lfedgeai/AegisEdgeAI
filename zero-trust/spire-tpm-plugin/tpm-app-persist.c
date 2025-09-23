// tpm_app_persist.c
// Persist an App Signing Key (AppSK) under Owner hierarchy.
// Auto-selects swtpm if present, else hardware TPM via device TCTI.
// Compatible with tpm2-tss 4.x.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <inttypes.h>
#include <sys/stat.h>

#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>
#include <tss2/tss2_tctildr.h>

#include <openssl/bn.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>

#define CHECK_RC(expr, label) \
    do { TSS2_RC _rc = (expr); if (_rc != TSS2_RC_SUCCESS) { \
        fprintf(stderr, "%s failed: 0x%x at %s:%d\n", #expr, _rc, __FILE__, __LINE__); \
        goto label; } } while (0)

static void die(const char *msg, TSS2_RC rc) {
    fprintf(stderr, "%s: 0x%x\n", msg, rc);
    exit(1);
}
static void diex(const char *msg) {
    fprintf(stderr, "%s\n", msg);
    exit(1);
}
static uint32_t env_u32(const char *name, uint32_t def) {
    const char *v = getenv(name);
    if (!v || !*v) return def;
    return (uint32_t)strtoul(v, NULL, 0);
}
static void write_file(const char *path, const uint8_t *buf, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) diex("fopen failed");
    if (fwrite(buf, 1, len, f) != len) { fclose(f); diex("fwrite failed"); }
    fclose(f);
}
static void tpm_public_to_pem(const TPM2B_PUBLIC *pub, const char *pem_path) {
    if (pub->publicArea.type != TPM2_ALG_RSA) diex("Non-RSA public key");
    const TPM2B_PUBLIC_KEY_RSA *rsa = &pub->publicArea.unique.rsa;
    const UINT32 exp = pub->publicArea.parameters.rsaDetail.exponent ?
                       pub->publicArea.parameters.rsaDetail.exponent : 65537;

    RSA *rsa_key = RSA_new();
    if (!rsa_key) diex("RSA_new failed");

    BIGNUM *n = BN_bin2bn(rsa->buffer, rsa->size, NULL);
    if (!n) { RSA_free(rsa_key); diex("BN_bin2bn failed"); }

    BIGNUM *e = BN_new();
    if (!e) { BN_free(n); RSA_free(rsa_key); diex("BN_new failed"); }
    BN_set_word(e, exp);

#if OPENSSL_VERSION_NUMBER >= 0x10100000L
    if (RSA_set0_key(rsa_key, n, e, NULL) != 1) { BN_free(n); BN_free(e); RSA_free(rsa_key); diex("RSA_set0_key failed"); }
#else
    rsa_key->n = n; rsa_key->e = e;
#endif

    FILE *f = fopen(pem_path, "wb");
    if (!f) { RSA_free(rsa_key); diex("fopen PEM failed"); }
    if (PEM_write_RSAPublicKey(f, rsa_key) != 1) { fclose(f); RSA_free(rsa_key); diex("PEM_write_RSAPublicKey failed"); }
    fclose(f);
    RSA_free(rsa_key);
}

static int path_exists(const char *p) {
    struct stat st;
    return (stat(p, &st) == 0);
}

static int swtpm_present(void) {
    const char *host = getenv("TPM_HOST"); if (!host) host = "127.0.0.1";
    const char *port = getenv("TPM_PORT"); if (!port) port = "2321";
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "nc -z %s %s >/dev/null 2>&1", host, port);
    int rc = system(cmd);
    return (rc == 0);
}

static TSS2_TCTI_CONTEXT* tcti_init_autoselect(void) {
    char tcti_conf[256] = {0};
    const char *host = getenv("TPM_HOST"); if (!host) host = "127.0.0.1";
    const char *port = getenv("TPM_PORT"); if (!port) port = "2321";

    if (swtpm_present()) {
        snprintf(tcti_conf, sizeof(tcti_conf), "swtpm:host=%s,port=%s", host, port);
    } else if (path_exists("/dev/tpmrm0")) {
        snprintf(tcti_conf, sizeof(tcti_conf), "device:/dev/tpmrm0");
    } else if (path_exists("/dev/tpm0")) {
        snprintf(tcti_conf, sizeof(tcti_conf), "device:/dev/tpm0");
    } else {
        fprintf(stderr, "[ERROR] No swtpm detected and no hardware TPM device found.\n");
        exit(1);
    }

    TSS2_TCTI_CONTEXT *tcti = NULL;
    TSS2_RC rc = Tss2_TctiLdr_Initialize(tcti_conf, &tcti);
    if (rc != TSS2_RC_SUCCESS || !tcti) {
        die("TctiLdr_Initialize", rc);
    }
    printf("[INFO] TCTI via loader: %s\n", tcti_conf);
    return tcti;
}

static ESYS_CONTEXT* esys_init(void) {
    TSS2_TCTI_CONTEXT *tcti = tcti_init_autoselect();
    ESYS_CONTEXT *ectx = NULL;
    TSS2_RC rc = Esys_Initialize(&ectx, tcti, NULL);
    if (rc != TSS2_RC_SUCCESS) die("Esys_Initialize", rc);
    rc = Esys_Startup(ectx, TPM2_SU_CLEAR);
    if (rc != TSS2_RC_SUCCESS) fprintf(stderr, "[WARN] Esys_Startup returned 0x%x\n", rc);
    return ectx;
}

static void esys_shutdown(ESYS_CONTEXT *ectx) {
    if (!ectx) return;
    TSS2_TCTI_CONTEXT *tcti = NULL;
    Esys_GetTcti(ectx, &tcti);
    Esys_Finalize(&ectx);
    if (tcti) {
        Tss2_TctiLdr_Finalize(&tcti);
    }
}

static void flush_all_transients(ESYS_CONTEXT *ctx) {
    TPMI_YES_NO more = TPM2_NO;
    TPMS_CAPABILITY_DATA *cap = NULL;
    TSS2_RC rc = Esys_GetCapability(ctx, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                                    TPM2_CAP_HANDLES, TPM2_TRANSIENT_FIRST, 64, &more, &cap);
    if (rc != TSS2_RC_SUCCESS || !cap) return;
    for (UINT32 i = 0; i < cap->data.handles.count; i++) {
        ESYS_TR tr = ESYS_TR_NONE;
        if (Esys_TR_FromTPMPublic(ctx, cap->data.handles.handle[i],
                                  ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &tr) == TSS2_RC_SUCCESS) {
            (void)Esys_FlushContext(ctx, tr);
        }
    }
    Esys_Free(cap);
}

int main(int argc, char **argv) {
    const char *force = (argc >= 2) ? argv[1] : "";
    const char *agent_ctx_path = (argc >= 3) ? argv[2] : "app.ctx";
    const char *agent_pubkey_pem = (argc >= 4) ? argv[3] : "appsk_pubkey.pem";

    uint32_t AK_HANDLE  = env_u32("AK_HANDLE",  0x8101000A);
    uint32_t APP_HANDLE = env_u32("APP_HANDLE", 0x8101000B);

    printf("[INFO] tpm-app-persist (auto hw/swtpm)\n");
    printf("[INFO] AK handle:  0x%08x\n", AK_HANDLE);
    printf("[INFO] APP handle: 0x%08x\n", APP_HANDLE);

    ESYS_CONTEXT *ctx = esys_init();
    if (!ctx) diex("ESYS context init failed");

    flush_all_transients(ctx);

    // Force mode: evict if present, then create anew
    if (strcmp(force, "--force") == 0) {
        ESYS_TR app_tr = ESYS_TR_NONE;
        if (Esys_TR_FromTPMPublic(ctx, APP_HANDLE,
                                  ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &app_tr) == TSS2_RC_SUCCESS) {
            (void)Esys_EvictControl(ctx, ESYS_TR_RH_OWNER, app_tr,
                                    ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, APP_HANDLE, NULL);
            (void)Esys_FlushContext(ctx, app_tr);
            printf("[INFO] Evicted existing AppSK at 0x%08x\n", APP_HANDLE);
        }
        printf("[INFO] Forcing creation of new AppSK...\n");
    } else {
        // Non-force: if already persisted, export and exit
        ESYS_TR existing = ESYS_TR_NONE;
        TSS2_RC rc = Esys_TR_FromTPMPublic(ctx, APP_HANDLE,
                                           ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &existing);
        if (rc == TSS2_RC_SUCCESS) {
            // Save context
            TPMS_CONTEXT *outctx = NULL;
            if (Esys_ContextSave(ctx, existing, &outctx) == TSS2_RC_SUCCESS && outctx) {
                uint8_t buf[sizeof(TPMS_CONTEXT)] = {0};
                size_t offset = 0;
                if (Tss2_MU_TPMS_CONTEXT_Marshal(outctx, buf, sizeof(buf), &offset) == TSS2_RC_SUCCESS) {
                    write_file(agent_ctx_path, buf, offset);
                    printf("[INFO] Existing AppSK context saved to %s\n", agent_ctx_path);
                }
                Esys_Free(outctx);
            }
            // Export public
            TPM2B_PUBLIC *pub = NULL;
            rc = Esys_ReadPublic(ctx, existing,
                                 ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                                 &pub, NULL, NULL);
            if (rc == TSS2_RC_SUCCESS && pub) {
                uint8_t pbuf[4096]; size_t poff = 0;
                if (Tss2_MU_TPM2B_PUBLIC_Marshal(pub, pbuf, sizeof(pbuf), &poff) == TSS2_RC_SUCCESS) {
                    write_file("appsk.pub", pbuf, poff);
                }
                tpm_public_to_pem(pub, agent_pubkey_pem);
                Esys_Free(pub);
            }
            printf("[SUCCESS] AppSK already persisted at 0x%08x; exported %s and appsk.pub\n",
                   APP_HANDLE, agent_pubkey_pem);
            esys_shutdown(ctx);
            return 0;
        } else {
            printf("[INFO] No existing AppSK at 0x%08x; creating new key...\n", APP_HANDLE);
        }
    }

    // 1) Create storage primary (Owner)
    TPM2B_SENSITIVE_CREATE inSensitivePrimary = {
        .size = sizeof(TPM2B_SENSITIVE_CREATE),
        .sensitive = { .userAuth = { .size = 0 }, .data = { .size = 0 } }
    };
    TPM2B_PUBLIC inPublicPrimary = {
        .size = 0,
        .publicArea = {
            .type = TPM2_ALG_RSA,
            .nameAlg = TPM2_ALG_SHA256,
            .objectAttributes =
                TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT |
                TPMA_OBJECT_SENSITIVEDATAORIGIN | TPMA_OBJECT_USERWITHAUTH |
                TPMA_OBJECT_RESTRICTED | TPMA_OBJECT_DECRYPT,
            .authPolicy = { .size = 0 },
            .parameters.rsaDetail = {
                .symmetric = { .algorithm = TPM2_ALG_AES, .keyBits.aes = 128, .mode.aes = TPM2_ALG_CFB },
                .scheme = { .scheme = TPM2_ALG_NULL },
                .keyBits = 2048,
                .exponent = 0,
            },
            .unique.rsa = { .size = 0 },
        }
    };
    TPM2B_DATA outsideInfo = { .size = 0 };
    TPML_PCR_SELECTION creationPCR = { .count = 0 };

    ESYS_TR primary = ESYS_TR_NONE;
    TPM2B_PUBLIC *outPublicPrimary = NULL;
    TPM2B_CREATION_DATA *creationData = NULL;
    TPM2B_DIGEST *creationHash = NULL;
    TPMT_TK_CREATION *creationTicket = NULL;

    CHECK_RC(Esys_CreatePrimary(
        ctx, ESYS_TR_RH_OWNER,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &inSensitivePrimary, &inPublicPrimary, &outsideInfo, &creationPCR,
        &primary, &outPublicPrimary, &creationData, &creationHash, &creationTicket), cleanup);

    // 2) Create AppSK (non-restricted signer)
    TPM2B_SENSITIVE_CREATE inSensitive = {
        .size = sizeof(TPM2B_SENSITIVE_CREATE),
        .sensitive = { .userAuth = { .size = 0 }, .data = { .size = 0 } }
    };
    TPM2B_PUBLIC inPublic = {
        .size = 0,
        .publicArea = {
            .type = TPM2_ALG_RSA,
            .nameAlg = TPM2_ALG_SHA256,
            .objectAttributes =
                TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT |
                TPMA_OBJECT_SENSITIVEDATAORIGIN | TPMA_OBJECT_USERWITHAUTH |
                TPMA_OBJECT_SIGN_ENCRYPT,
            .authPolicy = { .size = 0 },
            .parameters.rsaDetail = {
                .symmetric = { .algorithm = TPM2_ALG_NULL },
                .scheme = { .scheme = TPM2_ALG_RSASSA, .details.rsassa.hashAlg = TPM2_ALG_SHA256 },
                .keyBits = 2048,
                .exponent = 0,
            },
            .unique.rsa = { .size = 0 },
        }
    };

    TPM2B_PRIVATE *outPrivate = NULL;
    TPM2B_PUBLIC *outPublic = NULL;
    TPM2B_CREATION_DATA *creationData2 = NULL;
    TPM2B_DIGEST *creationHash2 = NULL;
    TPMT_TK_CREATION *creationTicket2 = NULL;

    CHECK_RC(Esys_Create(
        ctx, primary,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &inSensitive, &inPublic, &outsideInfo, &creationPCR,
        &outPrivate, &outPublic, &creationData2, &creationHash2, &creationTicket2), cleanup);

    // 3) Load AppSK
    ESYS_TR app_tr = ESYS_TR_NONE;
    CHECK_RC(Esys_Load(ctx, primary,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        outPrivate, outPublic, &app_tr), cleanup);

    // 4) Persist at APP_HANDLE
    ESYS_TR persistent_tr = ESYS_TR_NONE;
    CHECK_RC(Esys_EvictControl(ctx, ESYS_TR_RH_OWNER, app_tr,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        APP_HANDLE, &persistent_tr), cleanup);

    // 5) Export artifacts
    {
        uint8_t pbuf[4096]; size_t poff = 0;
        if (Tss2_MU_TPM2B_PUBLIC_Marshal(outPublic, pbuf, sizeof(pbuf), &poff) == TSS2_RC_SUCCESS) {
            write_file("appsk.pub", pbuf, poff);
        }
    }
    {
        uint8_t sbuf[4096]; size_t soff = 0;
        if (Tss2_MU_TPM2B_PRIVATE_Marshal(outPrivate, sbuf, sizeof(sbuf), &soff) == TSS2_RC_SUCCESS) {
            write_file("appsk.priv", sbuf, soff);
        }
    }
    tpm_public_to_pem(outPublic, agent_pubkey_pem);

    // Save context of the persisted object (best-effort)
    {
        ESYS_TR persisted = ESYS_TR_NONE;
        if (Esys_TR_FromTPMPublic(ctx, APP_HANDLE, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &persisted) == TSS2_RC_SUCCESS) {
            TPMS_CONTEXT *saved = NULL;
            if (Esys_ContextSave(ctx, persisted, &saved) == TSS2_RC_SUCCESS && saved) {
                uint8_t cbuf[sizeof(TPMS_CONTEXT)] = {0};
                size_t coff = 0;
                if (Tss2_MU_TPMS_CONTEXT_Marshal(saved, cbuf, sizeof(cbuf), &coff) == TSS2_RC_SUCCESS) {
                    write_file(agent_ctx_path, cbuf, coff);
                }
                Esys_Free(saved);
            }
        }
    }

    printf("[SUCCESS] AppSK persisted at 0x%08x, exported: appsk.pub, appsk.priv, %s, %s\n",
           APP_HANDLE, agent_pubkey_pem, agent_ctx_path);

cleanup:
    // Free creation outputs
    if (creationTicket2) Esys_Free(creationTicket2);
    if (creationHash2) Esys_Free(creationHash2);
    if (creationData2) Esys_Free(creationData2);
    if (outPublic) Esys_Free(outPublic);
    if (outPrivate) Esys_Free(outPrivate);

    if (creationTicket) Esys_Free(creationTicket);
    if (creationHash) Esys_Free(creationHash);
    if (creationData) Esys_Free(creationData);
    if (outPublicPrimary) Esys_Free(outPublicPrimary);

    // Flush objects if still loaded
    if (app_tr != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, app_tr);
    if (primary != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, primary);

    // Shutdown
    if (ctx) esys_shutdown(ctx);
    return 0;
}
