#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <tss2/tss2_esys.h>
#include <tss2/tss2_mu.h>
#include <tss2/tss2_tcti.h>
#include <tss2/tss2_tctildr.h>
#include <openssl/rsa.h>
#include <openssl/pem.h>
#include <openssl/bn.h>

#define AK_HANDLE_ENV "AK_HANDLE"
#define APP_HANDLE_ENV "APP_HANDLE"

int write_data_to_file(const char *filename, const uint8_t *data, size_t size) {
    FILE *f = fopen(filename, "wb");
    if (f == NULL) return 1;
    if (fwrite(data, 1, size, f) != size) { fclose(f); return 1; }
    fclose(f);
    return 0;
}

void log_error(const char *msg, TSS2_RC rc) {
    fprintf(stderr, "ERROR: %s (0x%x)\n", msg, rc);
}

int write_pem_key(const char *filename, TPM2B_PUBLIC *public_key) {
    if (public_key->publicArea.type != TPM2_ALG_RSA) return 1;
    BIGNUM *n = BN_bin2bn(public_key->publicArea.unique.rsa.buffer, public_key->publicArea.unique.rsa.size, NULL);
    BIGNUM *e = BN_new();
    if (public_key->publicArea.parameters.rsaDetail.exponent == 0) BN_set_word(e, 65537);
    else BN_set_word(e, public_key->publicArea.parameters.rsaDetail.exponent);
    RSA *rsa = RSA_new();
    RSA_set0_key(rsa, n, e, NULL);
    BIO *bio = BIO_new_file(filename, "w");
    if (bio == NULL) { RSA_free(rsa); return 1; }
    PEM_write_bio_RSAPublicKey(bio, rsa);
    BIO_free(bio);
    RSA_free(rsa);
    return 0;
}

int main(int argc, char *argv[]) {
    int force = 0;
    char *agent_ctx_path = "app.ctx";
    char *agent_pubkey_path = "appsk_pubkey.pem";

    struct option long_options[] = { {"force", no_argument, 0, 'f'}, {0, 0, 0, 0} };
    int opt;
    while ((opt = getopt_long(argc, argv, "f", long_options, NULL)) != -1) {
        if (opt == 'f') force = 1;
    }
    if (optind < argc) agent_ctx_path = argv[optind++];
    if (optind < argc) agent_pubkey_path = argv[optind++];

    uint32_t ak_handle = getenv(AK_HANDLE_ENV) ? strtol(getenv(AK_HANDLE_ENV), NULL, 16) : 0x8101000A;
    uint32_t app_handle = getenv(APP_HANDLE_ENV) ? strtol(getenv(APP_HANDLE_ENV), NULL, 16) : 0x8101000B;

    TSS2_TCTI_CONTEXT *tcti_context = NULL;
    ESYS_CONTEXT *esys_context = NULL;
    TSS2_RC rc;

    const char *tcti_env = getenv("TPM2TOOLS_TCTI");
    rc = Tss2_TctiLdr_Initialize(tcti_env ? tcti_env : "swtpm", &tcti_context);
    if (rc != TSS2_RC_SUCCESS) { log_error("TCTI init", rc); return 1; }
    rc = Esys_Initialize(&esys_context, tcti_context, NULL);
    if (rc != TSS2_RC_SUCCESS) { log_error("ESYS init", rc); Tss2_TctiLdr_Finalize(&tcti_context); return 1; }

    ESYS_TR app_handle_tr = ESYS_TR_NONE;
    rc = Esys_TR_FromTPMPublic(esys_context, app_handle, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &app_handle_tr);
    if (rc != TSS2_RC_SUCCESS && rc != TPM2_RC_HANDLE) { log_error("Esys_TR_FromTPMPublic for APP_HANDLE failed", rc); goto cleanup; }

    if (force) {
        rc = Esys_EvictControl(esys_context, ESYS_TR_RH_OWNER, app_handle_tr, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, app_handle, NULL);
        if (rc != TSS2_RC_SUCCESS && rc != TPM2_RC_BAD_AUTH) { log_error("Esys_EvictControl (force)", rc); }
    }

    TPM2B_PUBLIC *outPublic = NULL;
    rc = Esys_ReadPublic(esys_context, app_handle_tr, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &outPublic, NULL, NULL);
    if (rc == TSS2_RC_SUCCESS) {
        printf("[INFO] AppSK already exists.\n");
        Esys_Free(outPublic);
        goto cleanup;
    }

    TPM2B_PUBLIC primary_template = { .publicArea = {
        .type = TPM2_ALG_RSA, .nameAlg = TPM2_ALG_SHA256,
        .objectAttributes = TPMA_OBJECT_USERWITHAUTH | TPMA_OBJECT_RESTRICTED | TPMA_OBJECT_DECRYPT | TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT | TPMA_OBJECT_SENSITIVEDATAORIGIN,
        .parameters.rsaDetail = { .keyBits = 2048 },
    }};
    ESYS_TR primary_handle = ESYS_TR_NONE;
    TPM2B_PRIVATE *outPrivate = NULL;
    rc = Esys_CreatePrimary(esys_context, ESYS_TR_RH_OWNER, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, NULL, &primary_template, NULL, NULL, &primary_handle, &outPublic, NULL, NULL, NULL);
    if (rc != TSS2_RC_SUCCESS) { log_error("Esys_CreatePrimary", rc); goto cleanup; }

    TPM2B_PUBLIC app_key_template = { .publicArea = {
        .type = TPM2_ALG_RSA, .nameAlg = TPM2_ALG_SHA256,
        .objectAttributes = TPMA_OBJECT_USERWITHAUTH | TPMA_OBJECT_SIGN_ENCRYPT | TPMA_OBJECT_DECRYPT | TPMA_OBJECT_FIXEDTPM | TPMA_OBJECT_FIXEDPARENT | TPMA_OBJECT_SENSITIVEDATAORIGIN,
        .parameters.rsaDetail = { .keyBits = 2048, .scheme = { .scheme = TPM2_ALG_RSASSA, .details.rsassa.hashAlg = TPM2_ALG_SHA256 }},
    }};
    rc = Esys_Create(esys_context, primary_handle, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, NULL, &app_key_template, NULL, NULL, &outPrivate, &outPublic, NULL, NULL, NULL);
    if (rc != TSS2_RC_SUCCESS) { log_error("Esys_Create", rc); goto cleanup; }

    if (write_pem_key(agent_pubkey_path, outPublic)) { log_error("Failed to write PEM key", 0); }

    ESYS_TR app_key_handle = ESYS_TR_NONE;
    rc = Esys_Load(esys_context, primary_handle, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, outPrivate, outPublic, &app_key_handle);
    if (rc != TSS2_RC_SUCCESS) { log_error("Esys_Load", rc); goto cleanup; }

    TPMS_CONTEXT *app_context;
    rc = Esys_ContextSave(esys_context, app_key_handle, &app_context);
    if (rc == TSS2_RC_SUCCESS) {
        write_data_to_file(agent_ctx_path, app_context->contextBlob.buffer, app_context->contextBlob.size);
        Esys_Free(app_context);
    } else { log_error("Esys_ContextSave", rc); }

    rc = Esys_EvictControl(esys_context, ESYS_TR_RH_OWNER, app_key_handle, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, app_handle, NULL);
    if (rc != TSS2_RC_SUCCESS) { log_error("Esys_EvictControl", rc); goto cleanup; }

    ESYS_TR ak_handle_tr = ESYS_TR_NONE;
    rc = Esys_TR_FromTPMPublic(esys_context, ak_handle, ESYS_TR_NONE, ESYS_TR_NONE, ESYS_TR_NONE, &ak_handle_tr);
    if (rc == TSS2_RC_SUCCESS) {
        TPMT_SIG_SCHEME inScheme = { .scheme = TPM2_ALG_RSASSA, .details.rsassa.hashAlg = TPM2_ALG_SHA256 };
        TPM2B_DATA qualifyingData = { .size = 0 };
        TPM2B_ATTEST *certifyInfo = NULL;
        TPMT_SIGNATURE *signature = NULL;
        rc = Esys_Certify(esys_context, app_handle_tr, ak_handle_tr, ESYS_TR_PASSWORD, ESYS_TR_NONE, ESYS_TR_NONE, &qualifyingData, &inScheme, &certifyInfo, &signature);
        if (rc == TSS2_RC_SUCCESS) {
            write_data_to_file("appsig_info.bin", certifyInfo->attestationData, certifyInfo->size);
            uint8_t sig_bytes[sizeof(TPMT_SIGNATURE)];
            size_t sig_size = 0;
            Tss2_MU_TPMT_SIGNATURE_Marshal(signature, sig_bytes, sizeof(sig_bytes), &sig_size);
            write_data_to_file("appsig_cert.sig", sig_bytes, sig_size);
        } else { log_error("Esys_Certify", rc); }
        Esys_Free(certifyInfo);
        Esys_Free(signature);
    }
    if (ak_handle_tr != ESYS_TR_NONE) Esys_TR_Close(esys_context, &ak_handle_tr);

cleanup:
    if (primary_handle != ESYS_TR_NONE) Esys_FlushContext(esys_context, primary_handle);
    if (app_key_handle != ESYS_TR_NONE) Esys_FlushContext(esys_context, app_key_handle);
    if (app_handle_tr != ESYS_TR_NONE) Esys_TR_Close(esys_context, &app_handle_tr);
    Esys_Free(outPublic);
    Esys_Free(outPrivate);
    Esys_Finalize(&esys_context);
    Tss2_TctiLdr_Finalize(&tcti_context);
    return rc == TSS2_RC_SUCCESS ? 0 : 1;
}
