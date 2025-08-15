1. Make sure ek.pub is in PEM format If it’s already PEM (starts with -----BEGIN PUBLIC KEY-----), you’re good. If it’s in TPM2 binary form, first export it from the TPM as PEM:
# Example: convert a TPM2-style pub blob to PEM
tpm2_readpublic -c ek.ctx -f pem -o ek.pub

2. Convert to DER and hash The verifier logic typically does:
# Convert PEM → DER
openssl pkey -pubin -inform pem -in ek.pub -outform der > ek.der

# Hash and hex‑encode
sha256sum ek.der | awk '{print $1}'

You’ll get a 64‑character hex string, e.g.:
4f3c0dfb0f3b13c4b0f8bb674e3f7a20889746f18a466a63c27cb043db8f596d

3. Populate your allow‑list Append that fingerprint to ek_allowlist.txt on the verifier side:
echo "4f3c0dfb0f3b13c4b0f8bb674e3f7a20889746f18a466a63c27cb043db8f596d" >> ek_allowlist.txt
