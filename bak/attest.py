import argparse
import base64
import json
import subprocess
import sys
from pathlib import Path
import tempfile, os

def run_text(cmd, check=True):
    return subprocess.run(cmd, check=check, capture_output=True, text=True)

def run_bytes(cmd, check=True):
    return subprocess.run(cmd, check=check, capture_output=True, text=False)

# --- Detect CLI drift for tpm2 certify ---
def tpm2_certify_help():
    res = run_text(["tpm2", "certify", "--help"], check=False)
    return (res.stdout or "") + (res.stderr or "")

def certify_cmd(ak_ctx, appsk_ctx, attest_path, sig_path):
    help_out = tpm2_certify_help()
    if "-o" in help_out and "-s" in help_out:
        return ["tpm2", "certify", "-C", ak_ctx, "-c", appsk_ctx, "-g", "sha256",
                "-o", str(attest_path), "-s", str(sig_path)]
    if "--attest-file" in help_out and "--signature-file" in help_out:
        return ["tpm2", "certify", "-C", ak_ctx, "-c", appsk_ctx, "-g", "sha256",
                "--attest-file", str(attest_path), "--signature-file", str(sig_path)]
    if " -m " in help_out or "\n    -m" in help_out:
        return ["tpm2", "certify", "-C", ak_ctx, "-c", appsk_ctx, "-g", "sha256",
                "-m", str(attest_path), "-s", str(sig_path)]
    raise RuntimeError("Unknown tpm2 certify syntax")

# --- Detect CLI drift for tpm2 quote ---
def quote_cmd(ak_handle, pcrs, nonce, attest_path, sig_path, pcrs_json_path):
    help_out = run_text(["tpm2", "quote", "--help"], check=False)
    out_text = (help_out.stdout or "") + (help_out.stderr or "")
    if "-C" in out_text:
        return ["tpm2", "quote", "-C", ak_handle, "-g", "sha256", "-l", pcrs,
                "-q", str(nonce), "-m", attest_path, "-s", sig_path, "-o", pcrs_json_path]
    if "-c" in out_text:
        return ["tpm2", "quote", "-c", ak_handle, "-g", "sha256", "-l", pcrs,
                "-q", str(nonce), "-m", attest_path, "-s", sig_path, "-o", pcrs_json_path]
    raise RuntimeError("Unsupported tpm2 quote syntax")

# --- Robust EK export ---
def export_ek_pem(ek_handle):
    """Always return EK in RFC5280 SubjectPublicKeyInfo PEM."""
    try:
        ek_pem = run_bytes(["tpm2", "readpublic", "-c", ek_handle, "-f", "pem"]).stdout
        if b"-----BEGIN PUBLIC KEY-----" in ek_pem:
            return ek_pem
    except subprocess.CalledProcessError:
        pass

    with tempfile.NamedTemporaryFile(delete=False) as tmp_der:
        der_path = tmp_der.name
    try:
        subprocess.run(
            ["tpm2", "readpublic", "-c", ek_handle, "-o", der_path, "-f", "der"],
            check=True
        )
        ek_pem = run_bytes(
            ["openssl", "pkey", "-pubin", "-inform", "der", "-in", der_path, "-outform", "pem"]
        ).stdout
        if b"-----BEGIN PUBLIC KEY-----" not in ek_pem:
            raise RuntimeError("EK conversion did not yield a valid PEM public key")
        return ek_pem
    finally:
        try: os.unlink(der_path)
        except Exception: pass

def main():
    ap = argparse.ArgumentParser(description="TPM attester client")
    ap.add_argument("--verifier", default="http://127.0.0.1:8080", help="Base URL of verifier")
    ap.add_argument("--ak-handle", default="0x8101000A")
    ap.add_argument("--appsk-handle", default="0x8101000B")
    ap.add_argument("--ek-handle", default="0x81010001")
    ap.add_argument("--pcrs", default="sha256:0,1,7")
    args = ap.parse_args()

    import requests

    # 1) Fetch nonce
    r = requests.post(f"{args.verifier}/nonce", json={})
    r.raise_for_status()
    nonce_payload = r.json()
    nonce, nonce_id = nonce_payload["nonce"], nonce_payload["nonce_id"]

    # 2) Collect artifacts
    ek_pem = export_ek_pem(args.ek_handle)

    # Preferred: AK PEM (DER export + OpenSSL conversion)
    with tempfile.NamedTemporaryFile(delete=False) as tmp_der:
        der_path = tmp_der.name
    try:
        subprocess.run([
            "tpm2", "readpublic",
            "-c", args.ak_handle,
            "-f", "der",
            "-o", der_path
        ], check=True)
        ak_pub_pem = run_bytes([
            "openssl", "pkey",
            "-pubin", "-inform", "der",
            "-in", der_path,
            "-outform", "pem"
        ]).stdout
    finally:
        try: os.unlink(der_path)
        except FileNotFoundError:
            pass

    if b"-----BEGIN PUBLIC KEY-----" not in ak_pub_pem:
        print("ERROR: AK PEM export failed after DER→PEM conversion", file=sys.stderr)
        sys.exit(2)

    # Legacy: AK TPM2B_PUBLIC for transition/debug
    ak_pub_tpm2b = run_bytes(["tpm2", "readpublic", "-c", args.ak_handle]).stdout

    # AppSK public (TPM2B_PUBLIC)
    appsk_pub = run_bytes(["tpm2", "readpublic", "-c", args.appsk_handle]).stdout

    # 3) AK quote
    with tempfile.NamedTemporaryFile(delete=False) as fm, \
         tempfile.NamedTemporaryFile(delete=False) as fs, \
         tempfile.NamedTemporaryFile(delete=False, suffix=".json") as fp:
        fm_path, fs_path, fp_path = fm.name, fs.name, fp.name
    try:
        subprocess.run(quote_cmd(args.ak_handle, args.pcrs, nonce, fm_path, fs_path, fp_path), check=True)
        quote_bin = Path(fm_path).read_bytes()
        quote_sig = Path(fs_path).read_bytes()
        pcrs_json = Path(fp_path).read_bytes()
    finally:
        for p in (fm_path, fs_path, fp_path):
            try: os.unlink(p)
            except Exception: pass

    # 4) AK -> AppSK certify
    with tempfile.NamedTemporaryFile(delete=False) as fa, tempfile.NamedTemporaryFile(delete=False) as fs:
        fa_path, fs_path = fa.name, fs.name
    try:
        subprocess.run(certify_cmd(args.ak_handle, args.appsk_handle, fa_path, fs_path), check=True)
        certify_attest = Path(fa_path).read_bytes()
        certify_sig = Path(fs_path).read_bytes()
    finally:
        for p in (fa_path, fs_path):
            try: os.unlink(p)
            except Exception: pass

    # 5) Submit to verifier (send both AK forms; verifier will prefer PEM)
    payload = {
        "nonce_id": nonce_id,
        "nonce": nonce,
        "ek_pem": base64.b64encode(ek_pem).decode(),
        "ak_pub_pem": base64.b64encode(ak_pub_pem).decode(),
        "ak_pub_tpm2b": base64.b64encode(ak_pub_tpm2b).decode(),
        "appsk_pub": base64.b64encode(appsk_pub).decode(),
        "quote_attest": base64.b64encode(quote_bin).decode(),
        "quote_sig": base64.b64encode(quote_sig).decode(),
        "pcrs": base64.b64encode(pcrs_json).decode(),
        "certify_attest": base64.b64encode(certify_attest).decode(),
        "certify_sig": base64.b64encode(certify_sig).decode(),
    }

    rv = requests.post(f"{args.verifier}/attest", json=payload)
    try:
        rv.raise_for_status()
        print(json.dumps(rv.json(), indent=2))
    except Exception:
        print(rv.status_code, rv.text, file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()

