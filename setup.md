setup.sh
    │
    ├── Validate tools
    ├── Create kind cluster
    ├── Install Argo CD
    ├── Wait for Argo CD
    ├── Retrieve admin credentials
    └── Start Argo CD port-forward
             │
             ▼
        Argo CD ready
             │
             ▼
deploy.sh
    │
    ├── Configure Git credentials
    ├── Create user-app namespace
    ├── Apply application secret
    ├── Apply Argo CD Application
    ├── Wait for application
    ├── Verify workloads
    └── Start application port-forward