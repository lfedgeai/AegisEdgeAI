Continuous Rotation + Reload (The "Cloud-Native" App)

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



# Continuous Rotation + Reload (Cloud-Native App)

**Objective:** Demonstrate that a "cloud-native" application, which re-reads its certificate from disk on each request, can handle `cert-manager`'s CSI rotation automatically with zero downtime and no restarts.

This document contains two ways to prove this:
1.  **Main Test:** Using a continuous Python script.
2.  **Alternative Validation:** Using a continuous `curl` loop in a test pod.

---

## Main Test: Python Application

## Setup Procedure (Python App)

### Step 1: Start Minikube & Connect Docker
```bash
minikube start
minikube docker-env | Invoke-Expression
```

### Step 2: Install Cert-Manager
```bash
helm repo add jetstack [https://charts.jetstack.io](https://charts.jetstack.io)
helm repo update
helm install cert-manager jetstack/cert-manager `
  --namespace cert-manager `
  --create-namespace `
  --set installCRDs=true `
  --set csiDriver.enabled=true `
  --set csiDriver.spiffe.enabled=true
```
Wait for all 4 pods in `cert-manager` namespace to be running.

### Step 3: Build Backend Image
```bash
# Navigate to backend/ directory
cd backend
docker build -t py-backend:gunicorn .
cd ..
```

### Step 4: Build Frontend (Phase 1) Image
```bash
# Navigate to frontend/ directory
cd frontend
docker build --no-cache -t py-mtls-frontend:phase1 .
cd ..
```

### Step 5: Deploy All Resources
```bash
# Delete any old resources first
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl delete deployment backend-deployment --ignore-not-found=true
kubectl delete service backend-svc --ignore-not-found=true
kubectl delete certificate demo-ca --ignore-not-found=true
kubectl delete issuer demo-ca --ignore-not-found=true
kubectl delete clusterissuer selfsigned-ca --ignore-not-found=true

# Wait 30s for cleanup, then deploy
cd ..
kubectl apply -f ca-issuer.yaml
cd py-mtls-demo
kubectl apply -f backend.yaml
kubectl apply -f frontend/frontend.yaml
```


## 4. Testing & Validation (Python App)

# 4.1 trusted CA pod

### Step 1: Check connection with frontend
```bash
kubectl logs -l app=frontend
```

### Step 2: Observe the Success
You will see `SUCCESS` messages every 5 seconds. Wait for the 5-minute mark to pass.

**Expected Result:** The logs will **continue to show `SUCCESS`** without any interruption or errors. The certificate will expire, the CSI driver will rotate it, and the app will automatically pick up the new file on its next loop.

**Conclusion:** You have successfully demonstrated that this "cloud-native" application handles certificate rotation automatically with no downtime.
---

## 4.2 Rogue pod

# step 1: Find Your Specific Pod Name

```bash
kubectl logs -l app=backend -f
```
# step 2: Open another Terminal

```bash
# Step 1: Delete any old rogue pod, just in case
kubectl delete pod rogue-client --ignore-not-found=true

# Step 2: Run a new alpine pod and open a shell inside it
kubectl run rogue-client --image=alpine --rm -it -- /bin/sh

# Step 3: Inside the rogue-client pod's shell
apk update && apk add curl

# Step 4: Inside the rogue-client pod's shell
curl -v -k https://backend-svc:8443
```
**Expected Result:** 
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
* TLSv1.3 (OUT), TLS handshake, Certificate (11):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* TLSv1.3 (IN), TLS alert, unknown (628):
* OpenSSL SSL_read: OpenSSL/3.5.4: error:0A00045C:SSL routines::tlsv13 alert certificate required, errno 0
* closing connection #0
curl: (56) OpenSSL SSL_read: OpenSSL/3.5.4: error:0A00045C:SSL routines::tlsv13 alert certificate required, errno 0

# step 3: Open backend Terminal and Confirm Rejection on the Backend
In another terminal, check the logs of your backend pod. You will see the corresponding rejection message, confirming the backend actively denied the connection.

[2025-10-27 08:02:37 +0000] [8] [WARNING] Invalid request from ip=10.244.0.X: [SSL: PEER_DID_NOT_RETURN_A_CERTIFICATE] peer did not return a certificate


## 5. Alternative Validation (Stateless `curl` Test)

This test provides a clearer, more direct validation using a stateless `curl` command.

### Step 1: Clean Up Existing Frontend
Ensure any previous `frontend-deployment` (from Phase 1 or the Python test) is deleted.
```bash
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl get pods -l app=frontend
# (Wait until it says "No resources found")
```

### Step 2: deploy `curl-client.yaml` 
This pod mounts the CSI volume and requests a 1-minute certificate.

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
Let this run for several minutes. The 5-minute certificate will rotate multiple times, but the `SUCCESS` messages will **never stop**.

**Conclusion:** This test proves that any stateless client (like `curl`) that reads its certificate from disk for each request will experience zero downtime during automatic certificate rotation..
