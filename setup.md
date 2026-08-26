setup.sh
   │
   ├── Check prerequisites
   │      ├── docker
   │      ├── kubectl
   │      ├── kind
   │      └── curl
   │
   ├── Validate Docker
   │
   ├── Create kind cluster
   │
   ├── Create argocd namespace
   │
   ├── Install ArgoCD
   │
   ├── Wait for ArgoCD
   │
   └── Display access information
              │
              ▼
         ArgoCD ready
              │
              ▼
       GitLab repository
              │
              ▼
       Raw K8s manifests
              │
              ▼
       ArgoCD Application
              │
              ▼
       Node.js + MongoDB
