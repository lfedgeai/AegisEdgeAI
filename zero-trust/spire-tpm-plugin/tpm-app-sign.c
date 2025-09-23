#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <ctype.h>

#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>
#include <tss2/tss2_tctildr.h>
#include <openssl/sha.h>

#define CHECK_RC(expr, label) do { \
    TSS2_RC _rc = (expr); \
    if (_rc != TSS2_RC_SUCCESS) { \
        fprintf(stderr, "[ERROR] %s rc=0x%08x\n", #expr, _rc); \
        goto label; \
    } \
} while (0)

static int read_file(const char *path, uint8_t **buf_out, size_t *len_out) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("[ERROR] fopen"); return -1; }
    if (fseek(f, 0, SEEK_END) != 0) { perror("[ERROR] fseek"); fclose(f); return -1; }
    long sz = ftell(f);
    if (sz <= 0) { fclose(f); fprintf(stderr, "[ERROR] bad size for %s\n", path); return -1; }
    if (fseek(f, 0, SEEK_SET) != 0) { perror("[ERROR] fseek"); fclose(f); return -1; }
    uint8_t *buf = (uint8_t *)malloc((size_t)sz);
    if (!buf) { fclose(f); fprintf(stderr, "[ERROR] malloc\n"); return -1; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    fclose(f);
    if (rd != (size_t)sz) { free(buf); fprintf(stderr, "[ERROR] short read %s\n", path); return -1; }
    *buf_out = buf; *len_out = (size_t)sz;
    return 0;
}

static int write_file(const char *path, const uint8_t *buf, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror("[ERROR] fopen"); return -1; }
    size_t wr = fwrite(buf, 1, len, f);
    fclose(f);
    if (wr != len) { fprintf(stderr, "[ERROR] short write %s\n", path); return -1; }
    return 0;
}

static ESYS_CONTEXT *esys_init_from_env(void) {
    ESYS_CONTEXT *ctx = NULL;
    TSS2_TCTI_CONTEXT *tcti = NULL;
    const char *tcti_conf = getenv("TCTI");
    if (!tcti_conf || strlen(tcti_conf) == 0)
        tcti_conf = "swtpm:host=127.0.0.1,port=2321";
    TSS2_RC rc = Tss2_TctiLdr_Initialize(tcti_conf, &tcti);
    if (rc != TSS2_RC_SUCCESS) { fprintf(stderr, "[ERROR] TctiLdr_Initialize rc=0x%08x\n", rc); return NULL; }
    rc = Esys_Initialize(&ctx, tcti, NULL);
    if (rc != TSS2_RC_SUCCESS) { fprintf(stderr, "[ERROR] Esys_Initialize rc=0x%08x\n", rc); Tss2_TctiLdr_Finalize(&tcti); return NULL; }
    return ctx;
}

static int load_tpms_context(const char *path, TPMS_CONTEXT *out) {
    uint8_t *buf = NULL; size_t len = 0;
    if (read_file(path, &buf, &len) != 0) return -1;
    size_t off = 0;
    TSS2_RC rc = Tss2_MU_TPMS_CONTEXT_Unmarshal(buf, len, &off, out);
    free(buf);
    if (rc != TSS2_RC_SUCCESS) { fprintf(stderr, "[ERROR] Unmarshal TPMS_CONTEXT rc=0x%08x\n", rc); return -1; }
    return 0;
}

static int is_handle_string(const char *s) {
    // Accept “0x...” hex or decimal digits
    if (!s || !*s) return 0;
    if (strlen(s) > 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) return 1;
    for (const char *p = s; *p; ++p) if (!isdigit((unsigned char)*p)) return 0;
    return 1;
}

static ESYS_TR get_key_tr(ESYS_CONTEXT *ctx, const char *ctx_or_handle) {
    ESYS_TR key_tr = ESYS_TR_NONE;
    if (is_handle_string(ctx_or_handle)) {
        // Persistent handle path: create ESYS_TR from TPM public
        TPM2_HANDLE h = 0;
        if (ctx_or_handle[0] == '0' && (ctx_or_handle[1] == 'x' || ctx_or_handle[1] == 'X'))
            sscanf(ctx_or_handle, "%x", &h);
        else
            sscanf(ctx_or_handle, "%u", &h);
        TSS2_RC rc = Esys_TR_FromTPMPublic(ctx, h, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &key_tr);
        if (rc != TSS2_RC_SUCCESS) {
            fprintf(stderr, "[ERROR] TR_FromTPMPublic(0x%08x) rc=0x%08x\n", h, rc);
            return ESYS_TR_NONE;
        }
    } else {
        // Context file path: ContextLoad
        TPMS_CONTEXT tpms;
        if (load_tpms_context(ctx_or_handle, &tpms) != 0) return ESYS_TR_NONE;
        if (Esys_ContextLoad(ctx, &tpms, &key_tr) != TSS2_RC_SUCCESS) {
            fprintf(stderr, "[ERROR] ContextLoad failed\n");
            return ESYS_TR_NONE;
        }
    }
    return key_tr;
}

static void rsa_scheme_to_sig_scheme(const TPMT_RSA_SCHEME *rsa, TPMT_SIG_SCHEME *sig_out) {
    memset(sig_out, 0, sizeof(*sig_out));
    switch (rsa->scheme) {
    case TPM2_ALG_RSASSA:
        sig_out->scheme = TPM2_ALG_RSASSA;
        sig_out->details.rsassa.hashAlg = rsa->details.rsassa.hashAlg;
        break;
    case TPM2_ALG_RSAPSS:
        sig_out->scheme = TPM2_ALG_RSAPSS;
        sig_out->details.rsapss.hashAlg = rsa->details.rsapss.hashAlg;
        break;
    case TPM2_ALG_NULL:
    default:
        sig_out->scheme = TPM2_ALG_RSASSA;
        sig_out->details.rsassa.hashAlg = TPM2_ALG_SHA256;
        break;
    }
}

static void hex(const uint8_t *data, size_t len, char *out) {
    static const char *h = "0123456789abcdef";
    for (size_t i = 0; i < len; i++) {
        out[i*2]     = h[(data[i] >> 4) & 0xF];
        out[i*2 + 1] = h[data[i] & 0xF];
    }
    out[len*2] = '\0';
}

int main(int argc, char **argv) {
    if (argc != 5) {
        fprintf(stderr, "Usage: %s <context-or-handle> <message-bin> <signature-out> <siginfo-out>\n", argv[0]);
        return 1;
    }
    const char *ctx_or_handle = argv[1];
    const char *msg_path      = argv[2];
    const char *sig_path      = argv[3];
    const char *info_path     = argv[4];

    ESYS_CONTEXT *ctx = esys_init_from_env();
    if (!ctx) { fprintf(stderr, "[ERROR] ESYS init failed\n"); return 1; }

    ESYS_TR key_tr = get_key_tr(ctx, ctx_or_handle);
    if (key_tr == ESYS_TR_NONE) { Esys_Finalize(&ctx); return 1; }

    TPM2B_AUTH empty_auth = { .size = 0 };
    CHECK_RC(Esys_TR_SetAuth(ctx, key_tr, &empty_auth), done);

    // ReadPublic to get default scheme and attributes (best-effort)
    TPMT_SIG_SCHEME scheme;
    int restricted = 0;
    TPM2B_PUBLIC *pub = NULL;
    TSS2_RC rp = Esys_ReadPublic(ctx, key_tr, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &pub, NULL, NULL);
    if (rp == TSS2_RC_SUCCESS && pub) {
        restricted = (pub->publicArea.objectAttributes & TPMA_OBJECT_RESTRICTED) != 0;
        rsa_scheme_to_sig_scheme(&pub->publicArea.parameters.rsaDetail.scheme, &scheme);
    } else {
        memset(&scheme, 0, sizeof(scheme));
        scheme.scheme = TPM2_ALG_RSASSA;
        scheme.details.rsassa.hashAlg = TPM2_ALG_SHA256;
    }

    // Bound HMAC session for robust auth
    ESYS_TR sess = ESYS_TR_NONE;
    TPM2B_NONCE nonceCaller = { .size = 16 };
    memset(nonceCaller.buffer, 0xA5, nonceCaller.size);
    TPMT_SYM_DEF sym = { .algorithm = TPM2_ALG_NULL };
    CHECK_RC(Esys_StartAuthSession(ctx,
                                   ESYS_TR_NONE, key_tr, // bind to key
                                   ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                                   &nonceCaller, TPM2_SE_HMAC, &sym, TPM2_ALG_SHA256,
                                   &sess), done);

    // Read message and hash locally (SHA256)
    uint8_t *msg = NULL; size_t msg_len = 0;
    if (read_file(msg_path, &msg, &msg_len) != 0) goto done;
    uint8_t dig_buf[SHA256_DIGEST_LENGTH];
    SHA256(msg, msg_len, dig_buf);
    free(msg);

    TPM2B_DIGEST digest;
    memset(&digest, 0, sizeof(digest));
    digest.size = SHA256_DIGEST_LENGTH;
    memcpy(digest.buffer, dig_buf, digest.size);

    // Sign path
    TPMT_SIGNATURE *signature = NULL;
    TSS2_RC rc = Esys_Sign(ctx, key_tr,
                           sess, ESYS_TR_NONE, ESYS_TR_NONE,
                           &digest, &scheme, NULL, &signature);
    if (rc != TSS2_RC_SUCCESS) {
        fprintf(stderr, "[WARN] Direct sign rc=0x%08x; retry with TPM Hash + ticket\n", rc);
        // Hash inside TPM with RH_NULL to get ticket (even for unrestricted, as a simulator quirk workaround)
        TPM2B_MAX_BUFFER data;
        memset(&data, 0, sizeof(data));
        size_t limit = sizeof(data.buffer);
        // Reload message
        if (read_file(msg_path, &msg, &msg_len) != 0) goto done;
        data.size = (msg_len > limit) ? (UINT16)limit : (UINT16)msg_len;
        memcpy(data.buffer, msg, data.size);
        free(msg);

        TPM2B_DIGEST *digest_tpm = NULL;
        TPMT_TK_HASHCHECK *ticket = NULL;
        CHECK_RC(Esys_Hash(ctx, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE,
                           &data, TPM2_ALG_SHA256, ESYS_TR_RH_NULL,
                           &digest_tpm, &ticket), done);
        rc = Esys_Sign(ctx, key_tr,
                       sess, ESYS_TR_NONE, ESYS_TR_NONE,
                       digest_tpm, &scheme, ticket, &signature);
        Esys_Free(digest_tpm);
        Esys_Free(ticket);
        CHECK_RC(rc, done);
    }

    const uint8_t *sigbuf = NULL; size_t siglen = 0; const char *sig_name = "RSASSA";
    if (signature->sigAlg == TPM2_ALG_RSASSA) {
        sigbuf = signature->signature.rsassa.sig.buffer;
        siglen = signature->signature.rsassa.sig.size;
        sig_name = "RSASSA";
    } else if (signature->sigAlg == TPM2_ALG_RSAPSS) {
        sigbuf = signature->signature.rsapss.sig.buffer;
        siglen = signature->signature.rsapss.sig.size;
        sig_name = "RSAPSS";
    } else {
        fprintf(stderr, "[ERROR] Unexpected sigAlg: 0x%04x\n", signature->sigAlg);
        goto done;
    }

    if (write_file(sig_path, sigbuf, siglen) != 0) goto done;

    char dig_hex[65];
    hex(digest.buffer, digest.size, dig_hex);
    char json[256];
    int n = snprintf(json, sizeof(json),
                     "{ \"scheme\": \"%s\", \"hashAlg\": \"SHA256\", \"signature_len\": %zu }\n",
                     sig_name, siglen);
    if (n > 0) (void)write_file(info_path, (const uint8_t *)json, (size_t)n);

    printf("[SUCCESS] Signed %s -> %s, info: %s (sigAlg=%s)\n", msg_path, sig_path, info_path, sig_name);

done:
    if (signature) Esys_Free(signature);
    if (sess != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, sess);
    if (pub) Esys_Free(pub);
    if (key_tr != ESYS_TR_NONE) (void)Esys_FlushContext(ctx, key_tr);
    Esys_Finalize(&ctx);
    return 0;
}

