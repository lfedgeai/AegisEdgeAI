# frontend/app.py
import requests
import time
import logging
import os

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

CERT_PATH = "/etc/tls/tls.crt"
KEY_PATH = "/etc/tls/tls.key"
CA_PATH = "/etc/tls/ca.crt"
BACKEND_URL = "https://backend-svc:8443"

def check_certs():
    if not os.path.exists(CERT_PATH): return False
    if not os.path.exists(KEY_PATH): return False
    if not os.path.exists(CA_PATH): return False
    log.info("All certificates found.")
    return True

if __name__ == "__main__":
    log.info("Starting mTLS client...")
    while not check_certs():
        log.warning("Certs not yet available, sleeping 5s...")
        time.sleep(5)
    
    while True:
        try:
            log.info(f"Attempting to call backend at {BACKEND_URL} with mTLS...")
            response = requests.get(
                BACKEND_URL,
                verify=CA_PATH,
                cert=(CERT_PATH, KEY_PATH) # This line re-reads the files
            )
            response.raise_for_status()
            log.info(f"SUCCESS! Response from backend: {response.text.strip()}")
        except Exception as e:
            log.error(f"ERROR calling backend: {e}")
        time.sleep(5)