#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Argo CD Demo Application Deployment
# ============================================================

# -----------------------------
# Defaults
# -----------------------------
ARGOCD_NAMESPACE="argocd"
APP_NAMESPACE="user-app"
APP_NAME="node-mongo-app"

GIT_SECRET_FILE="argocd/argocd_git_secret.yaml"
APP_SECRET_FILE="user_app_secret.yaml"
APP_MANIFEST="argocd/application.yaml"

APP_PORT="4000"
LOCAL_APP_PORT="4000"

TIMEOUT="300"
POLL_INTERVAL="5"

# -----------------------------
# Logging
# -----------------------------
info() {
    echo "[INFO] $*"
}

success() {
    echo "[SUCCESS] $*"
}

error() {
    echo "[ERROR] $*" >&2
}

# -----------------------------
# Usage
# -----------------------------
usage() {
    cat <<EOF

Usage:
  ./deploy.sh [options]

Options:
  --git-secret       Argo CD Git credentials file
                     Default: ${GIT_SECRET_FILE}

  --app-secret       Application secret file
                     Default: ${APP_SECRET_FILE}

  --application      Argo CD Application manifest
                     Default: ${APP_MANIFEST}

  --app-name         Argo CD Application name
                     Default: ${APP_NAME}

  --app-namespace    Application namespace
                     Default: ${APP_NAMESPACE}

  --app-port         Container/service port
                     Default: ${APP_PORT}

  --local-port       Local port for application port-forward
                     Default: ${LOCAL_APP_PORT}

  --timeout          Maximum wait time in seconds
                     Default: ${TIMEOUT}

  --help             Display this help message

Example:

  ./deploy.sh \\
      --git-secret argocd/argocd_git_secret.yaml \\
      --app-secret user_app_secret.yaml \\
      --application argocd/application.yaml \\
      --app-name node-mongo-app \\
      --app-namespace user-app \\
      --local-port 4000

EOF
}

# -----------------------------
# Parse arguments
# -----------------------------
while [[ $# -gt 0 ]]; do

    case "$1" in

        --git-secret)
            GIT_SECRET_FILE="$2"
            shift 2
            ;;

        --app-secret)
            APP_SECRET_FILE="$2"
            shift 2
            ;;

        --application)
            APP_MANIFEST="$2"
            shift 2
            ;;

        --app-name)
            APP_NAME="$2"
            shift 2
            ;;

        --app-namespace)
            APP_NAMESPACE="$2"
            shift 2
            ;;

        --app-port)
            APP_PORT="$2"
            shift 2
            ;;

        --local-port)
            LOCAL_APP_PORT="$2"
            shift 2
            ;;

        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;

        --help)
            usage
            exit 0
            ;;

        *)
            error "Unknown parameter: $1"
            usage
            exit 1
            ;;

    esac

done

# ============================================================
# Configuration
# ============================================================

echo
echo "============================================================"
echo "             Argo CD Demo Application Deployment"
echo "============================================================"
echo

info "Configuration:"
echo "  ArgoCD namespace:       ${ARGOCD_NAMESPACE}"
echo "  Application name:       ${APP_NAME}"
echo "  Application namespace:  ${APP_NAMESPACE}"
echo "  Git credentials:        ${GIT_SECRET_FILE}"
echo "  Application secret:     ${APP_SECRET_FILE}"
echo "  Application manifest:   ${APP_MANIFEST}"
echo "  Application port:       ${LOCAL_APP_PORT}:${APP_PORT}"
echo "  Timeout:                ${TIMEOUT}s"
echo

# ============================================================
# Prerequisite checks
# ============================================================

info "Checking required tools..."

if ! command -v kubectl >/dev/null 2>&1; then
    error "kubectl is not installed or not in PATH."
    exit 1
fi

success "kubectl found: $(command -v kubectl)"

# ============================================================
# Verify Kubernetes connectivity
# ============================================================

info "Checking Kubernetes cluster connectivity..."

if ! kubectl cluster-info >/dev/null 2>&1; then
    error "Unable to connect to Kubernetes cluster."
    error "Run setup.sh first."
    exit 1
fi

success "Kubernetes cluster is reachable."

# ============================================================
# Verify Argo CD namespace
# ============================================================

info "Checking Argo CD namespace..."

if ! kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then
    error "Argo CD namespace '${ARGOCD_NAMESPACE}' does not exist."
    error "Run setup.sh first."
    exit 1
fi

success "Argo CD namespace exists."

# ============================================================
# Validate required files
# ============================================================

info "Checking required manifest files..."

required_files=(
    "${GIT_SECRET_FILE}"
    "${APP_SECRET_FILE}"
    "${APP_MANIFEST}"
)

for file in "${required_files[@]}"; do

    if [[ ! -f "${file}" ]]; then
        error "Required file not found: ${file}"
        exit 1
    fi

    success "Found: ${file}"

done

# ============================================================
# Configure Argo CD Git credentials
# ============================================================

echo
info "Configuring Argo CD Git repository credentials..."

kubectl apply -f "${GIT_SECRET_FILE}"

success "Argo CD Git credentials applied."

# ============================================================
# Verify Git credentials Secret
# ============================================================

info "Verifying Argo CD Git credentials..."

if ! kubectl get secret -n "${ARGOCD_NAMESPACE}" \
    -l "argocd.argoproj.io/secret-type=repository" \
    >/dev/null 2>&1; then

    error "Argo CD repository credentials could not be verified."
    exit 1
fi

success "Argo CD Git credentials verified."

# ============================================================
# Create application namespace
# ============================================================

echo
info "Creating application namespace '${APP_NAMESPACE}'..."

kubectl create namespace "${APP_NAMESPACE}" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

success "Application namespace is ready."

# ============================================================
# Apply application secret
# ============================================================

info "Applying application secret..."

kubectl apply -f "${APP_SECRET_FILE}"

success "Application secret applied."

# ============================================================
# Verify application secret
# ============================================================

info "Verifying application secret..."

if ! kubectl get secret -n "${APP_NAMESPACE}" \
    >/dev/null 2>&1; then

    error "Unable to verify application secret."
    exit 1
fi

success "Application secret verified."

# ============================================================
# Create Argo CD Application
# ============================================================

echo
info "Creating/updating Argo CD Application..."

kubectl apply -f "${APP_MANIFEST}"

success "Argo CD Application applied."

# ============================================================
# Verify Argo CD Application
# ============================================================

info "Verifying Argo CD Application..."

if ! kubectl get application "${APP_NAME}" \
    -n "${ARGOCD_NAMESPACE}" \
    >/dev/null 2>&1; then

    error "Argo CD Application '${APP_NAME}' was not created."
    exit 1
fi

success "Argo CD Application exists."

# ============================================================
# Wait for Argo CD synchronization and health
# ============================================================

echo
info "Waiting for Argo CD to synchronize the application..."
info "Maximum wait time: ${TIMEOUT}s"

start_time=$(date +%s)

while true; do

    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    if (( elapsed >= TIMEOUT )); then
        error "Timed out waiting for Argo CD application."
        echo
        kubectl get application "${APP_NAME}" \
            -n "${ARGOCD_NAMESPACE}" || true
        echo
        kubectl describe application "${APP_NAME}" \
            -n "${ARGOCD_NAMESPACE}" || true
        exit 1
    fi

    sync_status=$(kubectl get application "${APP_NAME}" \
        -n "${ARGOCD_NAMESPACE}" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null || true)

    health_status=$(kubectl get application "${APP_NAME}" \
        -n "${ARGOCD_NAMESPACE}" \
        -o jsonpath='{.status.health.status}' 2>/dev/null || true)

    info "Application status: Sync=${sync_status:-Unknown}, Health=${health_status:-Unknown}"

    if [[ "${sync_status}" == "Synced" &&
          "${health_status}" == "Healthy" ]]; then

        success "Application is Synced and Healthy."
        break
    fi

    sleep "${POLL_INTERVAL}"

done

# ============================================================
# Verify application workloads
# ============================================================

echo
info "Verifying application workloads..."

kubectl get all -n "${APP_NAMESPACE}"

# ============================================================
# Wait for user application Deployment
# ============================================================

info "Waiting for user application Deployment..."

if kubectl get deployment user-app \
    -n "${APP_NAMESPACE}" >/dev/null 2>&1; then

    if ! kubectl wait \
        --namespace "${APP_NAMESPACE}" \
        --for=condition=Available \
        deployment/user-app \
        --timeout="${TIMEOUT}s"; then

        error "user-app Deployment did not become ready."
        exit 1
    fi

    success "user-app Deployment is ready."

else

    error "user-app Deployment was not found."
    exit 1

fi

# ============================================================
# Start application port-forward
# ============================================================

echo
info "Starting application port-forward..."

# Check whether the requested local port is already in use.
if ss -ltn 2>/dev/null | grep -q ":${LOCAL_APP_PORT} "; then

    info "Local port ${LOCAL_APP_PORT} is already in use."
    info "Skipping application port-forward."

else

    kubectl port-forward \
        -n "${APP_NAMESPACE}" \
        "service/user-app" \
        "${LOCAL_APP_PORT}:${APP_PORT}" \
        >/tmp/argocd-demo-app-port-forward.log 2>&1 &

    PORT_FORWARD_PID=$!

    sleep 2

    if kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then

        success "Application port-forward is running."
        echo "  PID:  ${PORT_FORWARD_PID}"
        echo "  URL:  http://localhost:${LOCAL_APP_PORT}"

    else

        error "Failed to start application port-forward."
        cat /tmp/argocd-demo-app-port-forward.log
        exit 1

    fi

fi

# ============================================================
# Deployment summary
# ============================================================

echo
echo "============================================================"
echo "                  Deployment Complete"
echo "============================================================"
echo
echo "Argo CD Application:"
echo "  ${APP_NAME}"
echo
echo "Namespace:"
echo "  ${APP_NAMESPACE}"
echo
echo "Argo CD UI:"
echo "  https://localhost:8080"
echo
echo "Application:"
echo "  http://localhost:${LOCAL_APP_PORT}"
echo
echo "Health endpoint:"
echo "  http://localhost:${LOCAL_APP_PORT}/health"
echo
echo "============================================================"