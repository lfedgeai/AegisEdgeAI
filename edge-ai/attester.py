# attester.py
#!/usr/bin/env python3
import base64
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

VERIFIER_BASE = os.environ.get("VERIFIER_BASE", "http://127.0.0.1:5000")
EK_HANDLE = os.environ.get("EK_HANDLE", "0x81010001")
AK_HANDLE = os.environ.get("AK_HANDLE", "0x8101000A")
PCR_LIST  = os.environ.get("PCR_LIST",  "sha256:0,1,2,3,4,5,7")

def run(cmd, input_bytes=None):
    res = subprocess.run(cmd, input=input_bytes, capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(f"cmd failed: {' '.join(cmd)}\n{res.stderr.decode()}")
    return res

def http_get_json(url):
    with urllib.request.urlopen(url) as r:
        return json.loads(r.read().decode())

def http_post_json(url, payload):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read().decode())

def main():
    # 1) Get nonce from verifier
    nonce_resp = http_get_json(f"{VERIFIER_BASE}/nonce")
    nonce_id = nonce_resp["nonce_id"]
    nonce_hex = nonce_resp["nonce_hex"]

    with tempfile.TemporaryDirectory() as td:
        f_ekpub = os.path.join(td, "ek.pub.pem")
        f_akpub = os.path.join(td, "ak.pub.pem")
        f_akname = os.path.join(td, "ak.name")
        f_attest = os.path.join(td, "quote.attest")
        f_sig = os.path.join(td, "quote.sig")
        f_pcrs = os.path.join(td, "pcrs.bin")

        # 2) Export AK/EK public + AK name (for provenance; ak.name optional in this flow)
        # EK public (PEM)
        run(["tpm2", "readpublic", "-c", EK_HANDLE, "-o", f_ekpub, "-f", "pem", "-Q"])
        # AK public (PEM) + Name
        run(["tpm2", "readpublic", "-c", AK_HANDLE, "-o", f_akpub, "-f", "pem", "-n", f_akname, "-Q"])

        # 3) Read PCRs to a binary blob for checkquote
        # This file must be produced by tpm2 pcrread for checkquote to recompute digest correctly.
        run(["tpm2", "pcrread", "-L", PCR_LIST, "-o", f_pcrs, "-Q"])

        # 4) Perform TPM quote with the AK persistent handle against the nonce
        # Being explicit about scheme/hash for version drift resilience.
        quote_cmd = [
            "tpm2", "quote",
            "-C", AK_HANDLE,
            "-l", PCR_LIST,
            "-q", f"hex:{nonce_hex}",
            "-m", f_attest,
            "-s", f_sig,
            "-G", "rsassa",
            "-g", "sha256",
            "-Q"
        ]
        run(quote_cmd)

        # 5) Send evidence to verifier
        def b64(path, text=False):
            b = open(path, "rb").read()
            return base64.b64encode(b).decode()

        payload = {
            "nonce_id": nonce_id,
            "pcr_list": PCR_LIST,
            "quote_attest_b64": b64(f_attest),
            "quote_sig_b64": b64(f_sig),
            "pcrs_b64": b64(f_pcrs),
            "ak_pub_pem_b64": b64(f_akpub),
            # Optional extras you might store/log server-side:
            "extras": {
                "ak_name_hex": open(f_akname, "rb").read().hex(),
                "ek_pub_pem_b64": b64(f_ekpub),
            }
        }

        resp = http_post_json(f"{VERIFIER_BASE}/attest", payload)
        print(json.dumps(resp, indent=2))

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        sys.exit(1)

