### Step 1: Start Minikube & Connect Docker
```bash
minikube start
minikube docker-env | Invoke-Expression
```

### Step 2: Install Cert-Manager
```bash
helm repo add jetstack https://charts.jetstack.io
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
docker build -t py-backend:gunicorn-v2
cd ..
```

### Step 4: Build Frontend (Phase 1) Image
```bash
# Navigate to frontend/ directory
cd frontend
docker build --no-cache -t py-mtls-frontend:phase3-final-fix .
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
kubectl delete pod http-curl-client --ignore-not-found=true
kubectl delete pod curl-test-client --ignore-not-found=true

# Wait 30s for cleanup, then deploy
cd ..
kubectl apply -f ca-issuer.yaml
cd py-mtls-demo
kubectl apply -f backend.yaml
kubectl apply -f frontend.yaml
kubectl apply -f frontend-svc.yaml
kubectl apply -f curl-client.yaml
```

# Step 4: Run the 3-Terminal Test

🖥️ Terminal 1: Watch the frontend
This is your most important log. You'll see both the HTTP requests and the mTLS logs.

Bash

kubectl logs -f -l app=frontend
🖥️ Terminal 2: Watch the backend
This log will only show activity when the frontend's mTLS connection is working.

Bash

kubectl logs -f -l app=backend
🖥️ Terminal 3: Run the curl-pod
This command starts a new curl-pod that sends a request every 50 milliseconds (as requested by your mentor) to your frontend's new HTTP server.

Bash

kubectl run http-curl-client --image=alpine/curl:latest --rm -it -- sh -c 'while t