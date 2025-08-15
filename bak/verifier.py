import os
import re
import json
import time
import uuid
import hmac
import hashlib
from pathlib import Path
from typing import Dict, Any

from flask import Flask, request, jsonify, abort
import subprocess

from cryptography.hazmat.primitives import serialization, hashes
from cryptography.hazmat.backends import default_backend

# --- Config ---
EK_ALLOWLIST_FILE = os.environ.get("EK_ALLOWLIST", "ek_allowlist.txt")
NONCE_TTL_SEC = int(os.environ.get("NONCE_TTL_SEC", "300"))  # 5 min
MAX_BODY_BYTES = int(os.environ.get("MAX_BODY_BYTES", "524288"))  # 512KB
ALLOWED_HASH = "sha256"

app = Flask(__name__)
pending_nonces: Dict[str, Dict[str, Any]] = {}

def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True)

def ek_fingerprint_sha256_pem(pem_bytes: bytes) -> str:
    pub = serialization.load_pem_public_key(pem_bytes, backend=default_backend())
    der = pub.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return hashlib.sha256(der).hexdigest()

def ek_allowlisted(fp_hex: str) -> bool:
    p = Path(EK_ALLOWLIST_FILE)
    if not p.exists():
        return False
    entries = [ln.strip().lower() for ln in p.read_text().splitlines() if ln.strip()]
    return fp_hex.lower() in entries

def parse_name_alg_from_public(appsk_pub_bytes: bytes) -> str:
    # Dump to temp file to leverage tpm2 print
    import tempfile
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(appsk_pub_bytes)
        tmp = f.name
    try:
        out = run(["tpm2", "print", "-t", "TPM2B_PUBLIC", tmp]).stdout
    finally:
        try: os.unlink(tmp)
        except: pass
    m = re.search(r"name-alg:\s*\n\s*value:\s*([a-z0-9_]+)", out, flags=re.IGNORECASE)
    if not m:
        raise ValueError("Could not determine name-alg from AppSK public")
    return m.group(1).lower()

ALG_NAME_TO_ID = {"sha1":0x0004,"sha256":0x000B,"sha384":0x000C,"sha512":0x000D,"sm3_256":0x0012}
ALG_NAME_TO_HASH = {"sha1":hashlib.sha1,"sha256":hashlib.sha256,"sha384":hashlib.sha384,"sha512":hashlib.sha512}

def compute_name_from_public(appsk_pub_bytes: bytes, name_alg: str) -> bytes:
    if len(appsk_pub_bytes) < 4:
        raise ValueError("Invalid TPM2B_PUBLIC length")
    size = int.from_bytes(appsk_pub_bytes[0:2], "big")
    tpmt_public = appsk_pub_bytes[2:] if size == len(appsk_pub_bytes)-2 else appsk_pub_bytes
    hfun = ALG_NAME_TO_HASH.get(name_alg)
    if not hfun:
        raise ValueError(f"Unsupported name-alg: {name_alg}")
    digest = hfun(tpmt_public).digest()
    alg_id = ALG_NAME_TO_ID[name_alg]
    return alg_id.to_bytes(2, "big") + digest

def extract_attested_name(attest_bytes: bytes) -> bytes:
    import tempfile, binascii
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(attest_bytes)
        tmp = f.name
    try:
        out = run(["tpm2", "print", "-t", "TPMS_ATTEST", tmp]).stdout
    finally:
        try: os.unlink(tmp)
        except: pass
    m = re.search(r"\bname:\s*([0-9a-fA-F]+)", out)
    if not m:
        m = re.search(r"\bqualified name:\s*([0-9a-fA-F]+)", out)
    if not m:
        raise ValueError("Could not extract name from TPMS_ATTEST")
    hexs = re.sub(r"\s+", "", m.group(1))
    return bytes.fromhex(hexs)

# --- CLI drift handling for tpm2 checkquote ---
def _detect_checkquote_pcr_flag() -> dict:
    try:
        proc = subprocess.run(["tpm2", "checkquote", "--help"],
                              capture_output=True, text=True, check=False)
        txt = (proc.stdout or "") + (proc.stderr or "")
    except Exception:
        txt = ""
    return {
        "has_dash_p": "-p" in txt,
        "has_long_pcr": "--pcr" in txt,
        # Some legacy builds documented/accepted -o for PCR file
        "has_dash_o": ("\n  -o," in txt) or (" -o " in txt),
        "help": txt
    }

def _try_checkquote(cmd):
    """Run tpm2 checkquote, return (ok, error_text)."""
    try:
        subprocess.run(cmd, check=True, capture_output=True, text=True)
        return True, ""
    except subprocess.CalledProcessError as e:
        err = (e.stderr or "")
        if e.stdout:
            err += ("\n" + e.stdout)
        return False, err

def _ensure_tpm2b_public(path):
    """If the AK file is PEM, convert it to TPM2B_PUBLIC."""
    head = open(path, "rb").read(64)
    if b"BEGIN PUBLIC KEY" in head or b"BEGIN RSA PUBLIC KEY" in head:
        tpm2b_path = path + ".tpm2b"
        subprocess.run([
            "tpm2", "encodepem", "--public",
            "--input", path, "--output", tpm2b_path
        ], check=True)
        return tpm2b_path
    return path

def tpm2_checkquote(ak_pub_tpm2b_bytes: bytes, quote_bytes: bytes, sig_bytes: bytes,
                    pcrs_json_bytes: bytes, nonce_hex: str):
    import tempfile, os, subprocess

    with tempfile.NamedTemporaryFile(delete=False) as fbin, \
         tempfile.NamedTemporaryFile(delete=False) as fctx, \
         tempfile.NamedTemporaryFile(delete=False) as fpem, \
         tempfile.NamedTemporaryFile(delete=False) as fquote, \
         tempfile.NamedTemporaryFile(delete=False) as fsig, \
         tempfile.NamedTemporaryFile(delete=False, suffix=".json") as fpcr:

        # Write TPM2B_PUBLIC blob from attester
        fbin.write(ak_pub_tpm2b_bytes)
        fbin_path = fbin.name

        # Load it as an external public object into the NULL hierarchy
        subprocess.run([
            "tpm2", "loadexternal",
            "--hierarchy", "n",
            "--public", fbin_path,
            "--key-context", fctx.name
        ], check=True)

        # Dump it back out as PEM
        subprocess.run([
            "tpm2", "readpublic",
            "--context", fctx.name,
            "--output", fpem.name,
            "--format", "pem"
        ], check=True)

        pem_path = fpem.name

        # Quote, sig, and PCRs
        fquote.write(quote_bytes); quote_path = fquote.name
        fsig.write(sig_bytes);     sig_path   = fsig.name
        fpcr.write(pcrs_json_bytes); pcr_path = fpcr.name

    try:
        base = [
            "tpm2", "checkquote",
            "-u", pem_path,
            "-m", quote_path,
            "-s", sig_path,
            "-g", ALLOWED_HASH,
            "-q", nonce_hex
        ]
        # Try flags in order for PCR drift
        trials = [
            (base + ["-p", pcr_path], "using -p"),
            (base + ["--pcr", pcr_path], "using --pcr"),
            (base + ["-o", pcr_path], "using -o (legacy)")
        ]
        invalid = ("invalid option", "Unknown option", "unrecognized option")
        for cmd, mode in trials:
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode == 0:
                return
            if not any(m in (proc.stderr or "") for m in invalid):
                raise subprocess.CalledProcessError(proc.returncode, cmd,
                                                    output=proc.stdout,
                                                    stderr=proc.stderr)
        # fallback without PCRs
        subprocess.run(base, check=True)
    finally:
        for p in (fbin_path, fctx.name, pem_path, quote_path, sig_path, pcr_path):
            try: os.unlink(p)
            except FileNotFoundError:
                pass

def tpm2_verifysignature(attest_bytes, sig_bytes, ak_pem_bytes):
    import tempfile, os, subprocess
    with tempfile.NamedTemporaryFile(delete=False) as fmsg, \
         tempfile.NamedTemporaryFile(delete=False) as fsig, \
         tempfile.NamedTemporaryFile(delete=False, suffix=".pem") as fpk, \
         tempfile.NamedTemporaryFile(delete=False) as fctx:
        fmsg.write(attest_bytes); msg = fmsg.name
        fsig.write(sig_bytes); sig = fsig.name
        fpk.write(ak_pem_bytes); akpem = fpk.name
        ctxfile = fctx.name
    try:
        subprocess.check_call([
            "tpm2", "loadexternal",
            "--public", akpem,
            "--key-algorithm", "rsa",
            "--hierarchy", "o",
            "--context", ctxfile
        ])
        run([
            "tpm2", "verifysignature",
            "-c", ctxfile,
            "-g", ALLOWED_HASH,
            "-m", msg,
            "-s", sig
        ])
    finally:
        for p in (msg, sig, akpem, ctxfile):
            try: os.unlink(p)
            except: pass

def purge_expired_nonces():
    now = time.time()
    expired = [k for k,v in pending_nonces.items() if now - v["ts"] > NONCE_TTL_SEC]
    for k in expired:
        pending_nonces.pop(k, None)

@app.route("/nonce", methods=["POST"])
def issue_nonce():
    purge_expired_nonces()
    req = request.get_json(force=True, silent=True) or {}
    # Optional: bind nonce to an EK fingerprint hint to reduce replay window scope
    hint = req.get("ek_hint")  # opaque string the attester can include
    nid = uuid.uuid4().hex
    # 16 bytes nonce (hex)
    nonce = os.urandom(16).hex()
    pending_nonces[nid] = {"nonce": nonce, "ts": time.time(), "hint": hint}
    return jsonify({"nonce_id": nid, "nonce": nonce, "ttl_sec": NONCE_TTL_SEC})

@app.route("/attest", methods=["POST"])
def attest():
    purge_expired_nonces()
    if request.content_length and request.content_length > MAX_BODY_BYTES:
        abort(413)

    data = request.get_json(force=True, silent=True)
    if not data:
        return jsonify(ok=False, error="invalid JSON"), 400

    required = [
        "nonce_id", "nonce",
        "ek_pem",
        "appsk_pub",
        "quote_attest", "quote_sig", "pcrs",
        "certify_attest", "certify_sig"
    ]
    missing = [k for k in required if k not in data]
    if "ak_pub_pem" not in data and "ak_pub_tpm2b" not in data:
        missing.append("ak_pub_pem or ak_pub_tpm2b")
    if missing:
        return jsonify(ok=False, error=f"missing fields: {missing}"), 400

    # Validate nonce
    nid = data["nonce_id"]
    entry = pending_nonces.get(nid)
    if not entry or entry["nonce"] != data["nonce"]:
        return jsonify(ok=False, error="nonce not found/expired or mismatch"), 400
    pending_nonces.pop(nid, None)

    import base64, tempfile, os
    try:
        ek_pem        = base64.b64decode(data["ek_pem"])
        appsk_pub     = base64.b64decode(data["appsk_pub"])
        quote_attest  = base64.b64decode(data["quote_attest"])
        quote_sig     = base64.b64decode(data["quote_sig"])
        pcrs_json     = base64.b64decode(data["pcrs"])
        certify_attest= base64.b64decode(data["certify_attest"])
        certify_sig   = base64.b64decode(data["certify_sig"])

        if "ak_pub_pem" in data:
            print("******************* ak_pub_pem in data ******************************")
            ak_pub_pem_bytes = base64.b64decode(data["ak_pub_pem"])
            print(ak_pub_pem_bytes.decode())
        else:
            ak_pub_tpm2b = base64.b64decode(data["ak_pub_tpm2b"])
            with tempfile.NamedTemporaryFile(delete=False) as fbin, \
                 tempfile.NamedTemporaryFile(delete=False) as fctx, \
                 tempfile.NamedTemporaryFile(delete=False) as fpem:
                fbin.write(ak_pub_tpm2b)
                subprocess.run([
                    "tpm2", "loadexternal",
                    "--hierarchy", "n",
                    "--public", fbin.name,
                    "--key-context", fctx.name
                ], check=True)
                subprocess.run([
                    "tpm2", "readpublic",
                    "--context", fctx.name,
                    "--format", "pem",
                    "--output", fpem.name
                ], check=True)
                ak_pub_pem_bytes = Path(fpem.name).read_bytes()
            for p in (fbin.name, fctx.name, fpem.name):
                try: os.unlink(p)
                except: pass
    except Exception as e:
        return jsonify(ok=False, error=f"decode/AK convert: {e}"), 400

    # EK allowlist check
    try:
        ek_fp = ek_fingerprint_sha256_pem(ek_pem)
        if not ek_allowlisted(ek_fp):
            return jsonify(ok=False, error="EK not allowlisted", ek_fingerprint=ek_fp), 403
    except Exception as e:
        return jsonify(ok=False, error=f"EK parse/allowlist: {e}"), 400

    # AK quote verification (PEM path)
    try:
        with tempfile.NamedTemporaryFile(delete=False) as fpem, \
             tempfile.NamedTemporaryFile(delete=False) as fquote, \
             tempfile.NamedTemporaryFile(delete=False) as fsig, \
             tempfile.NamedTemporaryFile(delete=False, suffix=".json") as fpcr:
            fpem.write(ak_pub_pem_bytes); pem_path = fpem.name
            fquote.write(quote_attest); quote_path = fquote.name
            fsig.write(quote_sig);     sig_path   = fsig.name
            fpcr.write(pcrs_json);     pcr_path   = fpcr.name

        base = [
            "tpm2", "checkquote",
            "-u", pem_path,
            "-m", quote_path,
            "-s", sig_path,
            "-g", ALLOWED_HASH,
            "-q", data["nonce"]
        ]
        trials = [
            (base + ["-p", pcr_path]),
            (base + ["--pcr", pcr_path]),
            (base + ["-o", pcr_path]),
        ]
        invalid = ("invalid option", "Unknown option", "unrecognized option")
        for cmd in trials:
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode == 0:
                break
            if not any(m in (proc.stderr or "") for m in invalid):
                raise subprocess.CalledProcessError(proc.returncode, cmd,
                                                    output=proc.stdout,
                                                    stderr=proc.stderr)
        else:
            subprocess.run(base, check=True)
    except subprocess.CalledProcessError as e:
        return jsonify(ok=False, error="AK quote verification failed", stderr=e.stderr), 400

    # Verify AK signature over AppSK certify
    try:
        tpm2_verifysignature(certify_attest, certify_sig, ak_pub_pem_bytes)
    except subprocess.CalledProcessError as e:
        return jsonify(ok=False, error="AK signature over certify failed", stderr=e.stderr), 400

    # Compare AppSK Name
    try:
        name_alg      = parse_name_alg_from_public(appsk_pub)
        computed_name = compute_name_from_public(appsk_pub, name_alg)
        attested_name = extract_attested_name(certify_attest)
        if computed_name != attested_name:
            return jsonify(ok=False, error="AppSK Name mismatch"), 400
    except Exception as e:
        return jsonify(ok=False, error=f"AppSK name validation: {e}"), 400

    # Parse PCRs for caller info
    try:
        pcrs_obj = json.loads(pcrs_json.decode("utf-8"))
    except Exception:
        pcrs_obj = None

    return jsonify({
        "ok": True,
        "verdict": "TRUST_OK",
        "ek_fingerprint": ek_fp,
        "nonce": data["nonce"],
        "pcrs": pcrs_obj,
        "timestamp": int(time.time()),
    }), 200

if __name__ == "__main__":
    # Run: FLASK_ENV=production python3 verifier.py
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))

