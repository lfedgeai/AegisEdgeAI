# Continuous Rotation + Reload (Cloud-Native App)

**Objective:** Demonstrate that a "cloud-native" application, which re-reads its certificate from disk on each request, can handle `cert-manager`'s CSI rotation automatically with zero downtime and no restarts.

---

## How it Works

This phase simulates a modern, "cloud-native" application. Its core behavior is to be **stateless** and **re-read configuration** when needed.

1.  **Startup:** The pod starts, and the application (our original `requests` script) begins its loop.
2.  **Stateless Operation:** The application does **not** cache the certificate in memory. Instead, on *every loop*, it calls `requests.get(...)` and passes the *file paths* (`cert=(CERT_PATH, KEY_PATH)`) to the function.
3.  **Re-Reading:** The `requests` library is smart enough to re-read those file paths from the disk on each new connection attempt.
4.  **Automatic Rotation:** `cert-manager`'s CSI driver silently rotates the certificate files on the disk at the 5-minute mark.
5.  **The Success (The "Hot Reload"):**
    * The **pod's disk** now has the *new, valid* certificate.
    * The **application's loop** runs again.
    * It calls `requests.get(...)` and reads the file paths. This time, it automatically loads the *new, valid* certificate from the disk.
6.  **The Result:** The application presents the new certificate to the backend. The backend accepts it, and the log continues to show `SUCCESS` messages. There are **no errors and no downtime**.
7.  **The "Fix":** No fix is needed. The application is well-behaved and handles the rotation automatically.

**Conclusion:** This phase proves that when paired with a "cloud-native" app, the CSI driver provides **true, zero-downtime, continuous certificate rotation**.

---

## 1. Setup Procedure

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

### Step 4: Build Frontend (Phase 2) Image

```bash
# Navigate to frontend/ directory
cd frontend
docker build --no-cache -t py-mtls-frontend:phase2 .
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
kubectl apply -f ca-issuer.yaml
kubectl apply -f backend.yaml
kubectl apply -f frontend/frontend.yaml
```
*(Ensure your `frontend/frontend.yaml` is using the `py-mtls-frontend:phase2` image tag)*

---

## 2. Validation

This document contains three tests to prove Phase 2:
1.  **Test 1: mTLS Enforcement (Rogue Pod):** Prove the backend is rejecting clients without a cert.
2.  **Test 2: Automatic Rotation (Python App):** Prove the Python app survives a certificate rotation.
3.  **Test 3: Alternative Validation (Stateless `curl`):** Prove a stateless `curl` loop also survives rotation.

### Test 1: mTLS Enforcement (Rogue Pod)

This test validates that the backend is properly enforcing mTLS.

**1. Watch Backend Logs:**
In your **first terminal**, watch the backend logs.
```bash
kubectl logs -l app=backend -f
```

**2. Open a New Terminal:**
In a **second terminal**, run the following commands to create a temporary pod and try to connect without a certificate.

```bash
# Step 1: Delete any old rogue pod, just in case
kubectl delete pod rogue-client --ignore-not-found=true

# Step 2: Run a new alpine pod and open a shell inside it
kubectl run rogue-client --image=alpine --rm -it -- /bin/sh
```

**3. Inside the Rogue Pod's Shell:**
Run the following commands at the pod's (`/ #`) prompt.

```sh
# Step 3: Install curl
apk update && apk add curl

# Step 4: Attempt to connect (this will fail)
curl -v -k https://backend-svc:8443
```

**4. Observe Client-Side Error (Terminal 2):**
The `curl` command will fail with a "certificate required" error.
```
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
...
* OpenSSL SSL_read: OpenSSL/3.5.4: error:0A00045C:SSL routines::tlsv13 alert certificate required, errno 0
curl: (56) OpenSSL SSL_read: ... tlsv13 alert certificate required, errno 0
```

**5. Observe Server-Side Rejection (Terminal 1):**
Your backend log terminal will show the corresponding rejection message.
```
[2025-10-27 08:02:37 +0000] [8] [WARNING] Invalid request from ip=10.244.0.X: [SSL: PEER_DID_NOT_RETURN_A_CERTIFICATE] peer did not return a certificate
```
**Conclusion:** mTLS is successfully enforced. You can now type `exit` in Terminal 2.

---

### Test 2: Automatic Rotation (Python App)

This test validates that the "cloud-native" Python app handles rotation without downtime.

**1. Watch Frontend Logs:**
```bash
# Find your specific pod name
kubectl get pods -l app=frontend

# Watch the logs of that specific pod
kubectl logs -f <YOUR-POD-NAME-HERE>
```

**2. Observe the Success:**
You will see `SUCCESS` messages every 5 seconds. Wait for the 5-minute certificate duration to pass.

**Expected Result:** The logs will **continue to show `SUCCESS`** without any interruption or errors. The certificate will expire, the CSI driver will rotate it, and the app will automatically pick up the new file on its next loop.

**Conclusion:** The Python application successfully handles automatic rotation with zero downtime.

---

### Test 3: Alternative Validation (Stateless `curl` Test)

This test provides a clearer, more direct validation using a stateless `curl` command.

**1. Clean Up Existing Frontend:**
Ensure any previous `frontend-deployment` (from the Python test) is deleted.
```bash
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl get pods -l app=frontend
# (Wait until it says "No resources found")
```

**2. Deploy `curl-client.yaml`:**
This pod mounts the CSI volume and requests a 1-minute certificate. (Ensure you have this file created).
```bash
kubectl apply -f curl-client.yaml

# Wait for the pod to be 'Running'
kubectl get pod curl-test-client -w
```

**3. Run the Continuous Loop (in PowerShell):**
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
  
  if [ "$CERT_STATU" -eq 200 ]; then
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

**4. Observe the Success:**
You will see a continuous stream of:
```
Mon Oct 27 18:35:01 UTC 2025 - SUCCESS (HTTP 200)
Mon Oct 27 18:35:02 UTC 2025 - SUCCESS (HTTP 200)
...
```
Let this run for several minutes. The 1-minute certificate will rotate multiple times, but the `SUCCESS` messages will **never stop**.

**Conclusion:** This test proves that any stateless client (like `curl`) that reads its certificate from disk for each request will experience zero downtime during automatic certificate rotation.
