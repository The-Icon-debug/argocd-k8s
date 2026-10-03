# Argo CD GitOps Demo

A simple Kubernetes application used to demonstrate **Argo CD and GitOps**.

The application consists of:

- Node.js web application
- MongoDB
- Kubernetes Deployments and Services
- Kubernetes ConfigMap
- Kubernetes Secret
- Argo CD Application

The primary focus of this repository is **Argo CD**, rather than application development or Docker.

---

## Architecture

```text
Developer
    |
    | git push
    v
GitLab Repository
    |
    | Argo CD reconciliation
    v
+-----------------------+
|        Argo CD        |
|                       |
|  Application          |
|  Repo Server          |
|  Application Controller
+-----------+-----------+
            |
            | Kubernetes API
            v
+-----------------------+
|    Kubernetes Cluster |
|                       |
|  user-app namespace   |
|                       |
|  +----------------+   |
|  | Node.js App    |   |
|  +----------------+   |
|          |            |
|          v            |
|  +----------------+   |
|  | MongoDB        |   |
|  +----------------+   |
+-----------------------+
```

---

## Repository Structure

```text
argocd-demo/
│
├── argocd/
│   ├── application.yaml
│   └── argocd_git_secret.yaml
│
├── k8s/
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── mongodb-deployment.yaml
│   ├── mongodb-service.yaml
│   ├── user-app-deployment.yaml
│   └── user-app-service.yaml
│
├── setup.sh
│
├── deploy.sh
│
├── user_app_secret.yaml
└── README.md
```
---

## Docker Image

The `user-app` Deployment references:

```text
iconickyle/user-app:v1.0.0
```
This image is hosted in a private Docker registry and is therefore not
available to users without access to the repository.

To run the application locally, build and push your own image or use an existing image in the 
public Docker registry, mongo-express for instance:
https://hub.docker.com/_/mongo-express

Then update the image reference in:
```
k8s/user-app-deployment.yaml
```

## Prerequisites

The local lab uses:

- WSL
- Docker or Docker Desktop
- kubectl
- kind

Verify:

```bash
docker version
kubectl version
kind version
```

---

## Local Lab Setup

The `setup.sh` script automates:

- Tool validation
- kind cluster creation
- Argo CD namespace creation
- Argo CD installation in the argocd ns
- Argo CD readiness checks
- Initial admin password retrieval
- Argo CD port-forwarding: Access argocd from the UI or CLI

Example:

```bash
./scripts/setup.sh \
    --cluster-name argocd-lab \
    --k8s-version v1.36.1 \
    --argocd-version v3.4.4 \
    --argocd-port 8080
```

Once complete:

- Cluster is ready
- Argo CD is installed
- UI is accessible
- Admin credentials are displayed

Open:

```text
https://localhost:8080
```

---

## Application Deployment

The `deploy.sh` script automates the remaining application deployment steps:

- Argo CD Git repository credentials
- Application namespace creation
- Application Secret deployment
- Argo CD Application creation
- Argo CD Application status verification
- Application workload readiness checks
- Application port-forwarding

The actual secret files are maintained locally and are **not committed to Git**:

```text
argocd/argocd_git_secret.yaml
user_app_secret.yaml
```


## Private Git Repository Credentials

The repository is private, so Argo CD requires Git credentials.

The file:

```text
argocd/argocd_git_dummy_secret.yaml
```

contains **dummy/example values only**.

Update the values locally, before executing the deploy.sh script: argocd/argocd_git_secret.yaml.

---

## Application Secrets

The real application `secret.yaml` is intentionally **not stored in Git**.

The file:

```text
user_app_dummy_secret.yaml
```

contains **dummy/example values only**.

Update the values locally, before executing the deploy.sh script: user_app_secret.yaml

---

## Deploy the Application

Create the Argo CD Application: The deploy.sh handles the deployment by applying the argocd application 
manifest.

After that, Argo CD takes over management of the application's Kubernetes resources.

---

## Access the Application

Port-forward the application service: Handled by deploy.sh

```bash
kubectl port-forward \
    -n user-app \
    service/user-app \
    4000:4000
```

Open:

```text
http://localhost:4000
```

Health endpoint:

```text
http://localhost:4000/health
```

---

## Updating the Application

Update the replicas in:

```text
k8s/user-app-deployment.yaml
```

Commit and push:

```bash
git add .
git commit -m "Update deployment replica count"
git push
```

Argo CD automatically reconciles the change.

---

## Useful Commands

Check Argo CD Applications:

```bash
kubectl get applications -n argocd
```

Inspect Application:

```bash
kubectl describe application node-mongo-app -n argocd
```

Check application resources:

```bash
kubectl get all -n user-app
```

Watch pods:

```bash
kubectl get pods -n user-app -w
```

---

## Cleanup

Delete the local lab:

```bash
kind delete cluster --name argocd-lab
```

The environment can then be recreated using:

```bash
./scripts/setup.sh
```

---

## Notes

- `k8s/` contains the Kubernetes manifests managed by Argo CD.
- `argocd/application.yaml` defines the Argo CD Application.
- `argocd/argocd_git_dummy_secret.yaml` contains example credentials only.
- The real application secret is managed outside Git.
- The repository intentionally keeps the application simple so the focus remains on Argo CD and GitOps workflows.