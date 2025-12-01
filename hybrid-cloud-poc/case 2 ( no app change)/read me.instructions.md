# Demo: Phase 1 - "Legacy App" mTLS Rotation & Restart

This document provides a step-by-step guide to demonstrate a common failure scenario for "legacy" applications in a modern, automated mTLS environment.

## Overview

This demo proves that a "legacy" application, which reads its mTLS certificate into memory *only at startup*, will fail when `cert-manager`'s CSI driver automatically rotates the certificate on disk. It will also demonstrate that the **only** fix for this type of application is a forced `rollout restart`.

## Prerequisites

  * [Minikube](https://minikube.sigs.k8s.io/docs/start/)
  * [Docker](https://www.docker.com/get-started/)
  * [Helm](https://helm.sh/docs/intro/install/)
  * [kubectl](https://kubernetes.io/docs/tasks/tools/)
  * A PowerShell terminal (the provided commands are in PowerShell format)

-----

## Step 1: Start Minikube & Connect Docker Environment

First, start your local Kubernetes cluster.

```powershell
minikube start
```

Next, connect your local shell's Docker client to the Docker daemon *inside* the Minikube cluster.

```powershell
# This command configures your PowerShell session
minikube docker-env | Invoke-Expression
```

> **Note:** This is a **critical step**. It ensures that when you build Docker images in Step 3, they are built directly inside Minikube's environment. This allows the cluster to find the images locally (`imagePullPolicy: Never`) without needing an external registry.

-----

## Step 2: Install Cert-Manager with CSI-SPIFFE Driver

We will use Helm to install `cert-manager`. The flags `--set csiDriver.enabled=true` and `--set csiDriver.spiffe.enabled=true` are essential for this demo. They enable the [CSI (Container Storage Interface) driver](https://cert-manager.io/docs/usage/csi-driver/), which will automatically mount the mTLS certificates and keys directly into our application pods as a volume.

```powershell
# 1. Add the Jetstack Helm repository
helm repo add jetstack https://charts.jetstack.io

# 2. Update your repository list
helm repo update

# 3. Install cert-manager
helm install cert-manager jetstack/cert-manager `
  --namespace cert-manager `
  --create-namespace `
  --set installCRDs=true `
  --set csiDriver.enabled=true `
  --set csiDriver.spiffe.enabled=true
```

After running the install command, wait for all pods in the `cert-manager` namespace to be in the `Running` state before proceeding.

```powershell
# Check the status of the cert-manager pods
kubectl get pods -n cert-manager
```

-----

## Step 3: Build Application Docker Images

With your shell connected to Minikube's Docker daemon, build the application images. These commands assume you are in the root directory containing the `backend/` and `frontend/` sub-directories.

```powershell
# 1. Build the backend image
# (Note: The path './backend' tells Docker where to find the Dockerfile)
docker build -t py-backend:gunicorn ./backend

# 2. Build the frontend image
# (Note: The path './frontend' tells Docker where to find the Dockerfile)
docker build --no-cache -t py-mtls-frontend:phase1 ./frontend
```

-----

## Step 4: Deploy Kubernetes Applications

This step first cleans up any resources from a previous deployment and then applies all the new Kubernetes manifests.

### 4.1. Cleanup (Optional)

Run these commands to delete any old resources. The `--ignore-not-found=true` flag prevents errors if the resources don't exist.

```powershell
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl delete deployment backend-deployment --ignore-not-found=true
kubectl delete service backend-svc --ignore-not-found=true
kubectl delete certificate demo-ca --ignore-not-found=true
kubectl delete issuer demo-ca --ignore-not-found=true
kubectl delete clusterissuer selfsigned-ca --ignore-not-found=true
```

### 4.2. Deploy Resources

Apply all the `.yaml` manifests to create the services, deployments, and certificate issuers.

> **Note:** These commands assume all your `.yaml` files (`ca-issuer.yaml`, `backend.yaml`, `frontend.yaml`) are located in the current directory.

```powershell
# 1. Apply the Certificate Authority Issuer
kubectl apply -f ca-issuer.yaml

# 2. Apply the backend deployment and service
kubectl apply -f backend.yaml

# 3. Apply the frontend deployment (with 1-minute cert duration)
kubectl apply -f frontend.yaml
```

-----

## Step 5: Execute the Demo (Failure & Recovery)

This is the main test. You will observe the system working, then failing, and then being manually recovered.

### 5.1. Open Log Terminals

You will need two terminals to watch the logs from both the client and the server simultaneously.

**🖥️ Terminal 1: Watch the Frontend Logs**

```powershell
kubectl logs -f -l app=frontend
```

**🖥️ Terminal 2: Watch the Backend Logs**

```powershell
kubectl logs -f -l app=backend
```

### 5.2. Observe Initial Success (Time: 0m to 1m)

For the first minute, you will see both logs streaming `SUCCESS` messages with matching Request IDs.

  * **Frontend Log (Terminal 1):**
    ```
    [ReqID: 111-aaa...] SUCCESS! Response from backend: [ReqID: 111-aaa...] Success!
    ```
  * **Backend Log (Terminal 2):**
    ```
    [ReqID: 111-aaa...] Successful GET / request received...
    ```

### 5.3. Observe the Failure (Time: 1m+)

When the 1-minute certificate expires, `cert-manager`'s CSI driver will write a *new* certificate to the pod's disk. However, the "legacy" frontend app, which holds the *old* cert in memory, will suddenly begin to fail.

  * **Frontend Log (Terminal 1):**
    ```
    [ReqID: 222-bbb...] SSL ERROR calling backend: [SSL: SSLV3_ALERT_CERTIFICATE_EXPIRED]...
    [ReqID: 333-ccc...] SSL ERROR calling backend: [SSL: SSLV3_ALERT_CERTIFICATE_EXPIRED]...
    ```
  * **Backend Log (Terminal 2):**
    This log will show `certificate has expired` errors as the frontend pod is still trying to connect with its old, invalid certificate. You will **stop** seeing any `Successful GET` messages.
    ```
    [WARNING] Invalid request from ip=... [SSL: CERTIFICATE_VERIFY_FAILED] certificate has expired
    ```

### 5.4. Apply the Fix (Terminal 3)

Open a third terminal and manually force a rolling restart of the frontend deployment. This is the "fix" this legacy app requires.

```powershell
kubectl rollout restart deployment/frontend-deployment
```

### 5.5. Observe the Recovery

Go back to your log terminals. You will see the handoff.

  * **Frontend Log (Terminal 1):** The `kubectl logs -f` command will either stop or automatically connect to the *new* pod, which will immediately start showing `SUCCESS` messages.
  * **Backend Log (Terminal 2):** This is the clearest view. You will see a mix of `[WARNING] certificate has expired` (from the old, terminating pod) and new `[INFO] [ReqID: 444-ddd...] Successful GET` messages (from the new, starting pod). After a few seconds, the warnings will stop, and you will *only* see success messages.

**Conclusion:** This test successfully proves that the application is not cloud-native and requires a disruptive restart to handle certificate rotation.

-----

## Optional Test: Verify mTLS Security Enforcement

This test confirms that the backend is truly secure and will **reject** any connection that does not present a valid mTLS certificate signed by our CA.

### 1\. Watch Backend Logs (Terminal 1)

In one terminal, keep the backend logs running. You will see the rejection message here.

```powershell
kubectl logs -f -l app=backend
```

### 2\. Run a "Rogue" Pod (Terminal 2)

In a *second* terminal, run a temporary `alpine` pod. The `-it` gives you an interactive shell, and `--rm` ensures the pod is deleted when you exit.

```powershell
kubectl run rogue-client --image=alpine --rm -it -- sh
```

### 3\. Install curl (Inside the Rogue Pod)

Once inside the pod's shell (you'll see a `/ #` prompt), update the package manager and install `curl`:

```powershell
# / #
apk update && apk add curl
```

### 4\. Attempt Connection (Inside the Rogue Pod)

Now, try to connect to the backend's secure port. This client has *no certificate* to present, so the backend's `gunicorn` server will reject the connection at the TLS-level.

```powershell
# / #
curl -v -k https://backend-svc:8443
```

> **Note:** We use `-k` (insecure) only to tell `curl` to not validate the *server's* certificate (which is self-signed). The server, however, will still validate the *client's* certificate, which is the point of this test.

### 5\. Observe the Failure

You will see the `curl` command (in **Terminal 2**) fail.

**Expected `curl` Output (Failure):**

```
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
...
* OpenSSL SSL_read: ... tlsv13 alert certificate required, errno 0
curl: (56) OpenSSL SSL_read: ... tlsv13 alert certificate required, errno 0
```

Simultaneously, you will see the explicit rejection message in your backend logs (**Terminal 1**).

**Expected Backend Log (Rejection):**

```
[...timestamp...] [WARNING] Invalid request from ip=10.244.X.X: [SSL: PEER_DID_NOT_RETURN_A_CERTIFICATE] peer did not return a certificate
```

### 6\. Clean Up

In the rogue pod's terminal (Terminal 2), type `exit` and press Enter. The pod will be automatically deleted. This test confirms your backend is secure and correctly enforcing mTLS.