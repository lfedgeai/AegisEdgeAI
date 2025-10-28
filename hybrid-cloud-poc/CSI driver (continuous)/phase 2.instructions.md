## Phase 2: Continuous Rotation + Reload (The "Cloud-Native" App)

### How it Works

This phase simulates a modern, "cloud-native" application. Its core behavior is to be **stateless** and **re-read configuration** when needed.

1.  **Startup:** The pod starts, and the application (our original `requests` script) begins its loop.
2.  **Stateless Operation:** The application does **not** cache the certificate in memory. Instead, on *every loop*, it calls `requests.get(...)` and passes the *file paths* (`cert=(CERT_PATH, KEY_PATH)`) to the function.
3.  **Re-Reading:** The `requests` library is smart enough to re-read those file paths from the disk on each new connection attempt.
4.  **Automatic Rotation:** Just like in Phase 1, the `cert-manager` CSI driver silently rotates the certificate files on the disk at the 5-minute mark.
5.  **The Success (The "Hot Reload"):**
    * The **pod's disk** now has the *new, valid* certificate.
    * The **application's loop** runs again.
    * It calls `requests.get(...)` and reads the file paths. This time, it automatically loads the *new, valid* certificate from the disk.
6.  **The Result:** The application presents the new certificate to the backend. The backend accepts it, and the log continues to show `SUCCESS` messages. There are **no errors and no downtime**.
7.  **The "Fix":** No fix is needed. The application is well-behaved and handles the rotation automatically.

**Conclusion:** This phase proves that when paired with a "cloud-native" app, the CSI driver provides **true, zero-downtime, continuous certificate rotation**.



# Phase 2: Continuous Rotation + Reload (Cloud-Native App)

**Objective:** Demonstrate that a "cloud-native" application, which re-reads its certificate from disk on each request, can handle `cert-manager`'s CSI rotation automatically with zero downtime and no restarts.

This document contains two ways to prove this:
1.  **Main Test:** Using a continuous Python script.
2.  **Alternative Validation:** Using a continuous `curl` loop in a test pod.

---

## Main Test: Python Application

### 1. File Structure

This phase assumes the `backend` and `ca-issuer.yaml` are already running. The key change is in the **frontend** code and YAML.

```
.
├── ca-issuer.yaml     (Assumed running)
├── backend.yaml       (Assumed running)
├── backend/           (Assumed running)
└── frontend/
    ├── app.py         (New Phase 2 code)
    ├── Dockerfile
    ├── frontend.yaml  (New Phase 2 config)
    └── requirements.txt
```

---

## 2. Code & Configuration Files

The **Backend** and **CA** files are identical to Phase 1. The only change is the **Frontend**.

### `frontend/app.py` (Phase 2 Version)
This is the "cloud-native" app code that re-reads the cert on each request.
```python
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

            # --- KEY ---
            # By passing the file paths on each loop, the `requests`
            # library re-reads them, automatically picking up the new cert.
            response = requests.get(
                BACKEND_URL,
                verify=CA_PATH,
                cert=(CERT_PATH, KEY_PATH)
            )
            # -----------
            
            response.raise_for_status()
            log.info(f"SUCCESS! Response from backend: {response.text.strip()}")
        
        except requests.exceptions.SSLError as e:
            log.error(f"SSL ERROR calling backend: {e}")
        except requests.exceptions.ConnectionError as e:
            log.error(f"Connection ERROR calling backend: {e}")
        except requests.exceptions.RequestException as e:
            log.error(f"ERROR calling backend: {e}")
            
        time.sleep(5)
```

### `frontend/requirements.txt`
```
requests
```

### `frontend/Dockerfile`
```dockerfile
FROM python:3.10-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
```

### `frontend/frontend.yaml`
Note the new `image:` tag. The `duration:` remains short.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: py-mtls-frontend:phase2 # <--- Phase 2 Tag
        imagePullPolicy: Never
        volumeMounts:
        - name: certs
          mountPath: "/etc/tls"
          readOnly: true
      volumes:
      - name: certs
        csi:
          driver: csi.cert-manager.io
          readOnly: true
          volumeAttributes:
            csi.cert-manager.io/issuer-name: demo-ca
            csi.cert-manager.io/issuer-kind: Issuer
            csi.cert-manager.io/common-name: frontend-app
            csi.cert-manager.io/duration: 5m # <--- Short duration for testing
```

---

## 3. Setup Procedure (Python App)

### Step 1: Clean Up Phase 1
Ensure your Minikube and Docker env are active. Then, delete the old Phase 1 frontend.
```bash
# This command deletes the Phase 1 deployment
kubectl delete deployment frontend-deployment --ignore-not-found=true

# Wait for the pod to be fully terminated
kubectl get pods -l app=frontend
# (Wait until it says "No resources found")
```

### Step 2: Build Frontend (Phase 2) Image
```bash
# Navigate to frontend/ directory
cd frontend
docker build --no-cache -t py-mtls-frontend:phase2 .
cd ..
```

### Step 3: Deploy Frontend (Phase 2)
```bash
# Apply the new frontend.yaml
kubectl apply -f frontend/frontend.yaml
```

---

## 4. Testing & Validation (Python App)

### Step 1: Find Your Specific Pod Name
```bash
kubectl get pods -l app:frontend
# Copy the full name, e.g., frontend-deployment-9a1...-vxyz
```

### Step 2: Watch the Logs
```bash
# Paste your pod's name here
kubectl logs -f <YOUR-POD-NAME-HERE>
```

### Step 3: Observe the Success
You will see `SUCCESS` messages every 5 seconds. Wait for the 5-minute mark to pass.

**Expected Result:** The logs will **continue to show `SUCCESS`** without any interruption or errors. The certificate will expire, the CSI driver will rotate it, and the app will automatically pick up the new file on its next loop.

**Conclusion:** You have successfully demonstrated that this "cloud-native" application handles certificate rotation automatically with no downtime.

---

## 5. Alternative Validation (Stateless `curl` Test)

This test provides a clearer, more direct validation of the Phase 2 principle using a stateless `curl` command.

### Step 1: Clean Up Existing Frontend
Ensure any previous `frontend-deployment` (from Phase 1 or the Python test) is deleted.
```bash
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl get pods -l app=frontend
# (Wait until it says "No resources found")
```

### Step 2: Create `curl-client.yaml`
Create a new file with this content. This pod mounts the CSI volume and requests a 1-minute certificate.
```yaml
# curl-client.yaml
apiVersion: v1
kind: Pod
metadata:
  name: curl-test-client
spec:
  containers:
  - name: client
    image: alpine/curl:latest
    command: ["/bin/sh", "-c", "sleep 9999999"]
    volumeMounts:
    - name: certs
      mountPath: "/etc/tls"
  volumes:
  - name: certs
    csi:
      driver: csi.cert-manager.io
      readOnly: true
      volumeAttributes:
        csi.cert-manager.io/issuer-name: demo-ca
        csi.cert-manager.io/common-name: curl-client-app
        csi.cert-manager.io/duration: 1m # Short duration for fast testing
```

### Step 3: Apply and Wait for the Pod
```bash
kubectl apply -f curl-client.yaml

# Wait for the pod to be 'Running'
kubectl get pod curl-test-client -w
```

### Step 4: Run the Continuous Loop
To avoid all Windows shell quoting issues, we will create the script locally, copy it to the pod, and then execute it.

**1. Create `check.sh` locally (in PowerShell):**
```powershell
@'
#!/bin/sh
while true; do
  CERT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --cert /etc/tls/tls.crt \
    --key /etc/tls/tls.key \
    --cacert /etc/tls/ca.crt \
    -k https://backend-svc:8443)
  
  if [ "$CERT_STATUS" -eq 200 ]; then
    echo "$(date) - SUCCESS (HTTP 200)"
  else
    echo "$(date) - FAILURE (HTTP $CERT_STATUS)"
  fi
  sleep 1
done
'@ | Set-Content -Path check.sh
```

**2. Copy the script to the pod:**
```powershell
kubectl cp check.sh curl-test-client:/check.sh
```

**3. Fix line endings (CRITICAL for Windows):**
```powershell
kubectl exec -it curl-test-client -- sed -i 's/\r$//' /check.sh
```

**4. Make the script executable:**
```powershell
kubectl exec -it curl-test-client -- chmod +x /check.sh
```

**5. Run the script and observe:**
Open a **new terminal** and run this to watch the logs.
```powershell
kubectl exec -it curl-test-client -- sh /check.sh
```

### Step 5: Observe the Success
You will see a continuous stream of:
```
Mon Oct 27 18:35:01 UTC 2025 - SUCCESS (HTTP 200)
Mon Oct 27 18:35:02 UTC 2025 - SUCCESS (HTTP 200)
...
```
Let this run for several minutes. The 1-minute certificate will rotate multiple times, but the `SUCCESS` messages will **never stop**.

**Conclusion:** This test proves that any stateless client (like `curl`) that reads its certificate from disk for each request will experience zero downtime during automatic certificate rotation..