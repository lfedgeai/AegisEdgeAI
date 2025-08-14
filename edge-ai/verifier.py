# verifier.py
#!/usr/bin/env python3
import base64
import os
import subprocess
import tempfile
import uuid
from datetime import datetime, timedelta
from flask import Flask, request, jsonify

app = Flask(__name__)

NONCE_TTL = timedelta(minutes=5)
nonces = {}  # nonce_id -> {nonce: bytes, ts: datetime, used: bool}

def now():
    return datetime.utcnow()

@app.route("/nonce", methods=["GET"])
def get_nonce():
    nid = str(uuid.uuid4())
    nonce = os.urandom(32)
    nonces[nid] = {"nonce": nonce, "ts": now(), "used": False}
    return jsonify({
        "nonce_id": nid,
        "nonce_b64": base64.b64encode(nonce).decode(),
        "nonce_hex": nonce.hex()
    })

@app.route("/attest", methods=["POST"])
def attest():
    data = request.get_json(force=True)

    # Required fields (all base64 except pcr_list and nonce_id)
    required = [
        "nonce_id", "pcr_list",
        "quote_attest_b64", "quote_sig_b64",
        "pcrs_b64", "ak_pub_pem_b64"
    ]
    missing = [k for k in required if k not in data or not data[k]]
    if missing:
        return jsonify({"ok": False, "error": f"missing fields: {missing}"}), 400

    nid = data["nonce_id"]
    pcr_list = data["pcr_list"]

    # Validate nonce existence/TTL/one-time
    entry = nonces.get(nid)
    if not entry:
        return jsonify({"ok": False, "error": "unknown nonce_id"}), 400
    if entry["used"]:
        return jsonify({"ok": False, "error": "nonce already used"}), 400
    if now() - entry["ts"] > NONCE_TTL:
        return jsonify({"ok": False, "error": "nonce expired"}), 400

    nonce = entry["nonce"]
    nonce_hex = nonce.hex()

    # Materialize inputs to temp files for tpm2 checkquote
    with tempfile.TemporaryDirectory() as td:
        f_attest = os.path.join(td, "quote.attest")
        f_sig = os.path.join(td, "quote.sig")
        f_pcrs = os.path.join(td, "pcrs.bin")
        f_akpub = os.path.join(td, "ak.pub.pem")

        for (b64, path, mode) in [
            (data["quote_attest_b64"], f_attest, "wb"),
            (data["quote_sig_b64"],    f_sig,    "wb"),
            (data["pcrs_b64"],         f_pcrs,   "wb"),
            (data["ak_pub_pem_b64"],   f_akpub,  "wb"),
        ]:
            payload = base64.b64decode(b64)
            with open(path, mode) as f:
                f.write(payload)

        # Verify quote: signature, nonce binding, PCR digest
        # -f rsassa (RSA AK), -g sha256 (hash), -l pcr_list, -p pcrs.bin
        cmd = [
            "tpm2", "checkquote",
            "-u", f_akpub,
            "-m", f_attest,
            "-s", f_sig,
            "-f", "rsassa",
            "-g", "sha256",
            "-q", f"hex:{nonce_hex}",
            "-l", pcr_list,
            "-p", f_pcrs,
            "-Q",
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            entry["used"] = True  # one-time nonce
            return jsonify({
                "ok": True,
                "result": "quote_valid",
                "details": {
                    "pcr_list": pcr_list,
                    "nonce_id": nid
                }
            })
        except subprocess.CalledProcessError as e:
            return jsonify({
                "ok": False,
                "error": "checkquote_failed",
                "stderr": e.stderr.strip(),
                "stdout": e.stdout.strip(),
                "cmd": cmd
            }), 400

if __name__ == "__main__":
    # For dev only; put behind TLS/ingress in prod
    app.run(host="0.0.0.0", port=5000)

