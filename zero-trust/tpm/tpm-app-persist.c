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
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>
#include <tss2/tss2_tctildr.h>

#include <openssl/bn.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>

#define TPM_CONTEXT_MARSHAL_BUFFER_SIZE 4096

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

    if (RSA_set0_key(rsa_key, n, e, NULL) != 1) { BN_free(n); BN_free(e); RSA_free(rsa_key); diex("RSA_set0_key failed"); }

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
    const char *port_str = getenv("TPM_PORT"); if (!port_str) port_str = "2321";
    
    // Validate and parse port number
    char *endptr;
    long port_long = strtol(port_str, &endptr, 10);
    if (*endptr != '\0' || port_long < 1 || port_long > 65535) {
        fprintf(stderr, "[WARN] Invalid TPM_PORT '%s', defaulting to 2321\n", port_str);
        port_long = 2321;
    }
    
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return 0;
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port_long);
    
    if (inet_pton(AF_INET, host, &addr.sin_addr) <= 0) {
        close(sock);
        return 0;
    }
    
    // Set timeout for connection attempt (optional optimization)
    // If these fail, the connection test will still work but may take longer to timeout
    struct timeval timeout;
    timeout.tv_sec = 1;
    timeout.tv_usec = 0;
    if (setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
        fprintf(stderr, "[WARN] Failed to set SO_RCVTIMEO socket option\n");
    }
    if (setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout)) < 0) {
        fprintf(stderr, "[WARN] Failed to set SO_SNDTIMEO socket option\n");
    }
    
    int result = connect(sock, (struct sockaddr*)&addr, sizeof(addr));
    close(sock);
    return (result == 0);
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
        ESYS_TR existing = ESYS_TR_NONE;
        TSS2_RC rc = Esys_TR_FromTPMPublic(ctx, APP_HANDLE,
                                           ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &existing);
        if (rc == TSS2_RC_SUCCESS) {
            TPMS_CONTEXT *outctx = NULL;
            if (Esys_ContextSave(ctx, existing, &outctx) == TSS2_RC_SUCCESS && outctx) {
                uint8_t buf[TPM_CONTEXT_MARSHAL_BUFFER_SIZE] = {0};
                size_t offset = 0;
                if (Tss2_MU_TPMS_CONTEXT_Marshal(outctx, buf, sizeof(buf), &offset) == TSS2_RC_SUCCESS) {
                    write_file(agent_ctx_path, buf, offset);
                    printf("[INFO] Existing AppSK context saved to %s\n", agent_ctx_path);
                }
                Esys_Free(outctx);
            }
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
    TPM2B_SENSITIVE_CREATE inSensitivePrimary = { .size = sizeof(TPM2B_SENSITIVE_CREATE) };
    TPM2B_PUBLIC inPublicPrimary = { .size = 0 };
    inPublicPrimary.publicArea.type = TPM2_ALG_RSA;
    inPublicPrimary.publicArea.nameAlg = TPM2_ALG_SHA256;
    inPublicPrimary.publicArea.objectAttributes =
        TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT |
        TPMA_OBJECT_SENSITIVEDATAORIGIN | TPMA_OBJECT_USERWITHAUTH |
        TPMA_OBJECT_RESTRICTED | TPMA_OBJECT_DECRYPT;
    inPublicPrimary.publicArea.parameters.rsaDetail.symmetric.algorithm = TPM2_ALG_AES;
    inPublicPrimary.publicArea.parameters.rsaDetail.symmetric.keyBits.aes = 128;
    inPublicPrimary.publicArea.parameters.rsaDetail.symmetric.mode.aes = TPM2_ALG_CFB;
    inPublicPrimary.publicArea.parameters.rsaDetail.scheme.scheme = TPM2_ALG_NULL;
    inPublicPrimary.publicArea.parameters.rsaDetail.keyBits = 2048;

    TPM2B_DATA outsideInfo = { .size = 0 };
    TPML_PCR_SELECTION creationPCR = { .count = 0 };

    ESYS_TR primary = ESYS_TR_NONE;
    TPM2B_PUBLIC *outPublicPrimary = NULL;
    TPM2B_CREATION_DATA *creationData = NULL;
    TPM2B_DIGEST *creationHash = NULL;
    TPMT_TK_CREATION *creationTicket = NULL;

    CHECK_RC(Esys_CreatePrimary(ctx, ESYS_TR_RH_OWNER,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &inSensitivePrimary, &inPublicPrimary, &outsideInfo, &creationPCR,
        &primary, &outPublicPrimary, &creationData, &creationHash, &creationTicket), cleanup);
    TPM2B_SENSITIVE_CREATE inSensitive = { .size = sizeof(TPM2B_SENSITIVE_CREATE) };
    TPM2B_PUBLIC inPublic = { .size = 0 };
    inPublic.publicArea.type = TPM2_ALG_RSA;
    inPublic.publicArea.nameAlg = TPM2_ALG_SHA256;
    inPublic.publicArea.objectAttributes =
        TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT |
        TPMA_OBJECT_SENSITIVEDATAORIGIN | TPMA_OBJECT_USERWITHAUTH |
        TPMA_OBJECT_SIGN_ENCRYPT;
    inPublic.publicArea.authPolicy.size = 0;
    memset(&inPublic.publicArea.parameters.rsaDetail.symmetric, 0,
           sizeof(inPublic.publicArea.parameters.rsaDetail.symmetric));
    inPublic.publicArea.parameters.rsaDetail.symmetric.algorithm = TPM2_ALG_NULL;
    inPublic.publicArea.parameters.rsaDetail.scheme.scheme = TPM2_ALG_RSASSA;
    inPublic.publicArea.parameters.rsaDetail.scheme.details.rsassa.hashAlg = TPM2_ALG_SHA256;
    inPublic.publicArea.parameters.rsaDetail.keyBits = 2048;
    inPublic.publicArea.parameters.rsaDetail.exponent = 0;
    inPublic.publicArea.unique.rsa.size = 0;

    TPM2B_PRIVATE *outPrivate = NULL;
    TPM2B_PUBLIC *outPublic = NULL;
    TPM2B_CREATION_DATA *creationData2 = NULL;
    TPM2B_DIGEST *creationHash2 = NULL;
    TPMT_TK_CREATION *creationTicket2 = NULL;

    CHECK_RC(Esys_Create(ctx, primary,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        &inSensitive, &inPublic, &outsideInfo, &creationPCR,
        &outPrivate, &outPublic, &creationData2, &creationHash2, &creationTicket2), cleanup);
    // Load AppSK
    ESYS_TR app_tr = ESYS_TR_NONE;
    CHECK_RC(Esys_Load(ctx, primary,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        outPrivate, outPublic, &app_tr), cleanup);

    // Save context BEFORE eviction
    TPMS_CONTEXT *saved = NULL;
    if (Esys_ContextSave(ctx, app_tr, &saved) == TSS2_RC_SUCCESS && saved) {
        uint8_t cbuf[sizeof(TPMS_CONTEXT)] = {0};
        size_t coff = 0;
        if (Tss2_MU_TPMS_CONTEXT_Marshal(saved, cbuf, sizeof(cbuf), &coff) == TSS2_RC_SUCCESS) {
            write_file(agent_ctx_path, cbuf, coff);
            printf("[INFO] Saved AppSK context to %s\n", agent_ctx_path);
        }
        Esys_Free(saved);
    }

    // Persist at APP_HANDLE
    ESYS_TR persistent_tr = ESYS_TR_NONE;
    CHECK_RC(Esys_EvictControl(ctx, ESYS_TR_RH_OWNER, app_tr,
        ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE,
        APP_HANDLE, &persistent_tr), cleanup);

    // Export artifacts
    uint8_t pbuf[4096]; size_t poff = 0;
    if (Tss2_MU_TPM2B_PUBLIC_Marshal(outPublic, pbuf, sizeof(pbuf), &poff) == TSS2_RC_SUCCESS) {
        write_file("appsk.pub", pbuf, poff);
    }

    uint8_t sbuf[4096]; size_t soff = 0;
    if (Tss2_MU_TPM2B_PRIVATE_Marshal(outPrivate, sbuf, sizeof(sbuf), &soff) == TSS2_RC_SUCCESS) {
        write_file("appsk.priv", sbuf, soff);
    }

    tpm_public_to_pem(outPublic, agent_pubkey_pem);

    printf("[SUCCESS] AppSK persisted at 0x%08x, exported: appsk.pub, appsk.priv, %s\n",
           APP_HANDLE, agent_pubkey_pem);

cleanup:
    if (creationTicket2) Esys_Free(creationTicket2);
    if (creationHash2) Esys_Free(creationHash2);
    if (creationData2) Esys_Free(creationData2);
    if (outPublic) Esys_Free(outPublic);
    if (outPrivate) Esys_Free(outPrivate);

    if (creationTicket) Esys_Free(creationTicket);
    if (creationHash) Esys_Free(creationHash);
    if (creationData) Esys_Free(creationData);
    if (outPublicPrimary) Esys_Free(outPublicPrimary);

    if (app_tr != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, app_tr);
    if (primary != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, primary);

    esys_shutdown(ctx);
    return 0;
}

