# Kubernetes mTLS Demo with Cert-Manager CSI

This project demonstrates how to establish mutual TLS (mTLS) between a frontend and backend service running in Kubernetes.

It specifically uses **`cert-manager` with its CSI driver** to automatically provision, mount, and continuously rotate certificates for pods, enabling a secure, zero-trust communication channel.

The test setup involves:

  * A **backend** pod that only accepts mTLS connections.
  * A **frontend** pod that accepts standard HTTP requests and then uses mTLS to communicate with the backend.
  * A **curl-client** pod that continuously sends HTTP requests to the frontend to generate traffic.

## Prerequisites

  * [Minikube](https://minikube.sigs.k8s.io/docs/start/)
  * [Docker](https://www.docker.com/get-started/)
  * [Helm](https://helm.sh/docs/intro/install/)
  * [kubectl](https://kubernetes.io/docs/tasks/tools/)
  * A PowerShell terminal (for the provided commands)

-----

## Step 1: Start Minikube & Connect Docker Environment

First, start your local Kubernetes cluster.

```bash
minikube start
```

Next, connect your local shell's Docker client to the Docker daemon *inside* the Minikube cluster.

```powershell
# This command configures your PowerShell session
minikube docker-env | Invoke-Expression
```

> **Note:** This is a **critical step**. It ensures that when you build Docker images in Step 3, they are built directly inside Minikube's environment. This allows the cluster to find the images locally without needing an external registry.

-----

## Step 2: Install Cert-Manager with CSI-SPIFFE Driver

We will use Helm to install `cert-manager`. The specific flags `--set csiDriver.enabled=true` and `--set csiDriver.spiffe.enabled=true` are essential for this demo. They enable the [CSI (Container Storage Interface) driver](https://cert-manager.io/docs/usage/csi-driver/), which will automatically mount the mTLS certificates and keys directly into our application pods.

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

After running the install command, wait for all pods in the `cert-manager` namespace to be in the `Running` state before proceeding. You can check this with:
kubectl get pods -n cert-manager

-----

## Step 3: Build Application Docker Images

With your shell connected to Minikube's Docker daemon, build the images. These commands assume you are running them from the directory that contains your `backend` and `frontend` sub-directories.

```powershell
# 1. Build the backend image (pointing to the backend/ Dockerfile)
docker build -t py-backend:gunicorn-v2 .

# 2. Build the frontend image (pointing to the frontend/ Dockerfile)
docker build --no-cache -t py-mtls-frontend:phase3-final-fix .
```

-----

## Step 4: Deploy Kubernetes Applications

This step first cleans up any resources from a previous deployment and then applies all the new Kubernetes manifests.

### 4.1. Cleanup (Optional)

Run these commands to delete any old resources. The `--ignore-not-found=true` flag prevents errors if the resources don't exist.

```bash
kubectl delete deployment frontend-deployment --ignore-not-found=true
kubectl delete deployment backend-deployment --ignore-not-found=true
kubectl delete service backend-svc --ignore-not-found=true
kubectl delete certificate demo-ca --ignore-not-found=true
kubectl delete issuer demo-ca --ignore-not-found=true
kubectl delete clusterissuer selfsigned-ca --ignore-not-found=true
kubectl delete pod http-curl-client --ignore-not-found=true
kubectl delete pod curl-test-client --ignore-not-found=true
```

### 4.2. Deploy Resources

Apply all the `.yaml` manifests to create the services, deployments, and certificate issuers.

> **Note:** These commands assume all your `.yaml` files (`ca-issuer.yaml`, `backend.yaml`, etc.) are located in the current directory.

```bash
# 1. Apply the Certificate Authority Issuer
kubectl apply -f ca-issuer.yaml

# 2. Apply the backend deployment and service
kubectl apply -f backend.yaml

# 3. Apply the frontend deployment
kubectl apply -f frontend.yaml

# 4. Apply the frontend service (ClusterIP)
kubectl apply -f frontend-svc.yaml

# 5. Apply the test client pod
kubectl apply -f curl-client.yaml
```

-----

## Step 5: Verify mTLS with a 3-Terminal Test

This test setup allows us to observe the entire communication flow in real-time. Open three separate terminals.

### 🖥️ Terminal 1: Watch the Frontend Logs

This is your most important log. It will show two things:

1.  The incoming HTTP requests from the `curl-test-client`.
2.  The mTLS "handshake" logs as it securely connects to the backend.

<!-- end list -->

```bash
kubectl logs -f -l app=frontend
```

### 🖥️ Terminal 2: Watch the Backend Logs

This log will **only show activity** if the frontend successfully authenticates using its mTLS certificate. If this log remains empty, the mTLS connection is failing.

```bash
kubectl logs -f -l app=backend
```

### 🖥️ Terminal 3: Run the Test Client

This terminal will run a script inside the `curl-test-client` pod to send a new JSON request to the frontend every 50 milliseconds.

**1. Create the `check-id.sh` script locally**

Paste this entire block into your PowerShell terminal. This creates a file named `check-id.sh` in your current directory.

```powershell
@'
#!/bin/sh
i=0
while true; do
  i=$((i+1))
  
  # This curl command sends the JSON payload with the incrementing ID
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{\"id\":$i}" \
    http://frontend-svc:8080
    
  sleep 0.05
done
'@ | Set-Content -Path check-id.sh
```

**2. Copy, Fix, and Run the Script in the Pod**

Run these four commands in order:

```powershell
# 1. Copy the new script to the persistent pod
kubectl cp check-id.sh curl-test-client:/check-id.sh

# 2. Fix Windows line endings (CRITICAL)
# This 'sed' command removes '\r' characters that Windows adds
kubectl exec -it curl-test-client -- sed -i 's/\r$//' /check-id.sh

# 3. Make the script executable
kubectl exec -it curl-test-client -- chmod +x /check-id.sh

# 4. Run the script!
kubectl exec -it curl-test-client -- sh /check-id.sh
```

### Expected Outcome (Step 5)

If everything is working correctly:

  * **Terminal 3** will show a continuous stream of `Request X: 200`.
  * **Terminal 1** will show logs for both the incoming HTTP POST request *and* the mTLS connection to the backend.
  * **Terminal 2** will show logs confirming it received the request from the frontend.

-----

## Step 6: (Optional) Test mTLS Enforcement (Rogue Pod Test)

This test confirms that the backend is truly secure and will **reject** any connection that does not present a valid mTLS certificate.

### Step 6.1: Watch Backend Logs (Terminal 1)

In one terminal, keep the backend logs running. You will see the rejection message here.

```bash
kubectl logs -f -l app=backend
```

### Step 6.2: Run the Rogue Pod (Terminal 2)

In a *second* terminal, run a temporary `alpine` pod. The `-it` gives you an interactive shell, and `--rm` ensures the pod is deleted when you exit.

```bash
kubectl run rogue-client --image=alpine --rm -it -- sh
```

### Step 6.3: Install curl (Inside the Rogue Pod)

Once inside the pod's shell (you'll see a `/ #` prompt), install `curl`:

```bash
apk update && apk add curl
```

### Step 6.4: Attempt Connection (Inside the Rogue Pod)

Now, try to connect to the backend's secure port (`https://backend-svc:8443`). This attempt will fail.

```bash
curl -v -k https://backend-svc:8443
```

### Step 6.5: Observe the Failure

You will see the `curl` command (in **Terminal 2**) fail. The output clearly shows the server requested a certificate, but the client (our rogue pod) did not provide one.

**Expected Output (`curl` failure):**

```
* TLSv1.3 (IN), TLS handshake, Request CERT (13):
...
* OpenSSL SSL_read: ... tlsv13 alert certificate required, errno 0
curl: (56) OpenSSL SSL_read: ... tlsv13 alert certificate required, errno 0
```

Simultaneously, you will see the rejection message in your backend logs (**Terminal 1**).

**Expected Output (Backend Log):**

```
[...timestamp...] [WARNING] Invalid request from ip=10.244.X.X: [SSL: PEER_DID_NOT_RETURN_A_CERTIFICATE] peer did not return a certificate
```

### Step 6.6: Clean Up

In the rogue pod's terminal (Terminal 2), type `exit` and press Enter. The pod will be automatically deleted. This test confirms your backend is secure and correctly enforcing mTLS.