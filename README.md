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

The demo follows the GitOps model:

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
|  Repo Server           |
|  Application Controller|
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
