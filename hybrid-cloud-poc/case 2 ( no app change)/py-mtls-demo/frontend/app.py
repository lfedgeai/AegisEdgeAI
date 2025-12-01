import http.client
import ssl
import time
import logging
import os
import uuid  # <-- NEW: Import UUID for request IDs

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
log = logging.getLogger(__name__)

CERT_PATH = "/etc/tls/tls.crt"
KEY_PATH = "/etc/tls/tls.key"
CA_PATH = "/etc/tls/ca.crt"
BACKEND_HOST = "backend-svc"
BACKEND_PORT = 8443

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

    # --- KEY ---
    # Create an SSL context ONCE and load the certs into memory.
    log.info("Creating persistent SSLContext and loading certs into memory...")
    try:
        context = ssl.create_default_context(ssl.Purpose.SERVER_AUTH, cafile=CA_PATH)
        context.load_cert_chain(certfile=CERT_PATH, keyfile=KEY_PATH)
        log.info("Certs successfully loaded into memory.")
    except Exception as e:
        log.error(f"Failed to create SSLContext: {e}")
        exit(1)
    # -----------

    while True:
        conn = None
        # --- NEW: Generate Request ID ---
        request_id = str(uuid.uuid4())
        # --------------------------------

        try:
            log.info(f"[ReqID: {request_id}] Attempting to call backend at https://{BACKEND_HOST}:{BACKEND_PORT} with mTLS...")

            conn = http.client.HTTPSConnection(
                host=BACKEND_HOST,
                port=BACKEND_PORT,
                context=context  # Use the cached context
            )
            
            # --- NEW: Add headers ---
            headers = {"X-Request-ID": request_id}
            conn.request("GET", "/", headers=headers)
            # --------------------------

            response = conn.getresponse()
            data = response.read().decode()
            
            if response.status == 200:
                log.info(f"[ReqID: {request_id}] SUCCESS! Response from backend: {data.strip()}")
            else:
                log.error(f"[ReqID: {request_id}] HTTP ERROR! Status: {response.status}, Response: {data.strip()}")

        except ssl.SSLError as e:
            # Add Request ID to all error logs
            log.error(f"[ReqID: {request_id}] SSL ERROR calling backend: {e}")
        except Exception as e:
            log.error(f"[ReqID: {request_id}] GENERIC ERROR calling backend: {e}")
        finally:
            if conn:
                conn.close()

        time.sleep(5)