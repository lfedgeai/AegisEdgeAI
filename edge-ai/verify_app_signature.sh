tpm2_hash -C o -g sha256 -t digest.ticket -o msg.digest msg.bin
tpm2_sign -c app.ctx -g sha256 -o sig.bin msg.bin
tpm2_verifysignature -c app.ctx -g sha256 -m msg.bin -s sig.bin
