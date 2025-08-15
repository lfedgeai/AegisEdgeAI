# Nonce is 12
tpm2_quote -c app.ctx -l sha256:0,1 -m appsk_quote.msg -s appsk_quote.sig -o appsk_quote.pcrs -q 12 -g sha256
tpm2 flushcontext -t
tpm2_readpublic -c app.ctx -o appsk_pubkey.pem -f pem
tpm2_checkquote -u appsk_pubkey.pem   -m appsk_quote.msg   -s appsk_quote.sig   -f appsk_quote.pcrs   -g sha256   -q 12
