tpm2 flushcontext -t
tpm2_certify -C ak.ctx -c app.ctx -g sha256 -o app_certify.out -s app_certify.sig
