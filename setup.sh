#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# ArgoCD Local Lab Setup
#
# Creates:
#   - kind Kubernetes cluster
#   - ArgoCD namespace
#   - ArgoCD installation
#   - ArgoCD port-forward
#   - ArgoCD initial admin credentials
#
# Does NOT deploy the Node.js/MongoDB application.
#
# Example:
#   ./setup.sh \
#       --cluster-name argocd-lab \
#       --kubernetes-version v1.36.1 \
#       --argocd-version v3.4.4 \
#       --argocd-port 8080
#
# ============================================================


# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------

CLUSTER_NAME="argocd-lab"
KUBERNETES_VERSION="v1.36.1"
ARGOCD_VERSION="v3.4.4"
ARGOCD_NAMESPACE="argocd"
ARGOCD_PORT="8080"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STATE_DIR="${SCRIPT_DIR}/.argocd-lab"
PORT_FORWARD_PID_FILE="${STATE_DIR}/port-forward.pid"
PORT_FORWARD_LOG_FILE="${STATE_DIR}/port-forward.log"


# ------------------------------------------------------------
# Colours
# ------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'


# ------------------------------------------------------------
# Logging
# ------------------------------------------------------------

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}


# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------

usage() {
    cat <<EOF

ArgoCD Local Lab Setup

Usage:
    $0 [OPTIONS]

Options:

    --cluster-name NAME
        Kind cluster name.

        Default:
            ${CLUSTER_NAME}

    --kubernetes-version VERSION
        Kubernetes version used by the kind node image.

        Default:
            ${KUBERNETES_VERSION}

        Example:
            --kubernetes-version v1.36.1

    --argocd-version VERSION
        ArgoCD version to install.

        Default:
            ${ARGOCD_VERSION}

        Example:
            --argocd-version v3.4.4

    --argocd-namespace NAME
        Kubernetes namespace for ArgoCD.

        Default:
            ${ARGOCD_NAMESPACE}

    --argocd-port PORT
        Local port used to expose the ArgoCD UI.

        Default:
            ${ARGOCD_PORT}

        Example:
            --argocd-port 8080

    --help
        Display this help message.

Example:

    $0 \\
        --cluster-name argocd-lab \\
        --kubernetes-version v1.36.1 \\
        --argocd-version v3.4.4 \\
        --argocd-port 8080

EOF
}


# ------------------------------------------------------------
# Argument parsing
# ------------------------------------------------------------

parse_args() {

    while [[ $# -gt 0 ]]; do

        case "$1" in

            --cluster-name)
                CLUSTER_NAME="${2:?Missing value for --cluster-name}"
                shift 2
                ;;

            --kubernetes-version)
                KUBERNETES_VERSION="${2:?Missing value for --kubernetes-version}"
                shift 2
                ;;

            --argocd-version)
                ARGOCD_VERSION="${2:?Missing value for --argocd-version}"
                shift 2
                ;;

            --argocd-namespace)
                ARGOCD_NAMESPACE="${2:?Missing value for --argocd-namespace}"
                shift 2
                ;;

            --argocd-port)
                ARGOCD_PORT="${2:?Missing value for --argocd-port}"
                shift 2
                ;;

            --help|-h)
                usage
                exit 0
                ;;

            *)
                error "Unknown argument: $1"
                echo
                usage
                exit 1
                ;;

        esac

    done
}


# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

cleanup() {

    local exit_code=$?

    if [[ ${exit_code} -ne 0 ]]; then
        error "Setup failed."
        error "Review the output above for details."
    fi

    exit "${exit_code}"
}

trap cleanup EXIT


# ------------------------------------------------------------
# Command checks
# ------------------------------------------------------------

check_command() {

    local command_name="$1"

    if ! command -v "${command_name}" >/dev/null 2>&1; then
        error "Required command '${command_name}' was not found."
        return 1
    fi

    info "Found ${command_name}: $(command -v "${command_name}")"
}


check_prerequisites() {

    info "Checking required tools..."

    check_command docker
    check_command kubectl
    check_command kind
    check_command curl

    echo

    info "Docker version:"
    docker --version

    info "kubectl version:"
    kubectl version --client --short 2>/dev/null || kubectl version --client

    info "kind version:"
    kind version

    echo
}


# ------------------------------------------------------------
# Docker validation
# ------------------------------------------------------------

check_docker() {

    info "Checking Docker connectivity..."

    if ! docker info >/dev/null 2>&1; then
        error "Docker is not available."
        error "Make sure Docker Desktop is running and WSL integration is enabled."
        exit 1
    fi

    success "Docker is available."
}


# ------------------------------------------------------------
# Kind cluster
# ------------------------------------------------------------

cluster_exists() {

    kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"
}


create_kind_cluster() {

    if cluster_exists; then

        success "Kind cluster '${CLUSTER_NAME}' already exists."

    else

        info "Creating kind cluster '${CLUSTER_NAME}'..."

        kind create cluster \
            --name "${CLUSTER_NAME}" \
            --image "kindest/node:${KUBERNETES_VERSION}"

        success "Kind cluster '${CLUSTER_NAME}' created."

    fi
}


configure_kubectl() {

    local context="kind-${CLUSTER_NAME}"

    info "Configuring kubectl context..."

    kubectl config use-context "${context}" >/dev/null

    success "kubectl context set to '${context}'."
}


verify_cluster() {

    info "Verifying Kubernetes cluster..."

    kubectl cluster-info >/dev/null

    kubectl wait \
        --for=condition=Ready \
        node \
        --all \
        --timeout=120s

    success "Kubernetes cluster is ready."

    echo

    kubectl get nodes

    echo
}


# ------------------------------------------------------------
# ArgoCD
# ------------------------------------------------------------

create_argocd_namespace() {

    if kubectl get namespace "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then

        success "Namespace '${ARGOCD_NAMESPACE}' already exists."

    else

        info "Creating namespace '${ARGOCD_NAMESPACE}'..."

        kubectl create namespace "${ARGOCD_NAMESPACE}"

        success "Namespace '${ARGOCD_NAMESPACE}' created."

    fi
}


install_argocd() {

    local manifest_url

    manifest_url="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

    info "Installing ArgoCD ${ARGOCD_VERSION}..."

    info "Manifest:"
    echo "  ${manifest_url}"

    kubectl apply \
        --server-side \
        -n "${ARGOCD_NAMESPACE}" \
        -f "${manifest_url}"

    success "ArgoCD manifests applied."
}


wait_for_argocd() {

    local timeout="600s"

    info "Waiting for all ArgoCD deployments to become ready..."
    info "Maximum wait time: ${timeout}"

    if ! kubectl wait \
        --namespace "${ARGOCD_NAMESPACE}" \
        --for=condition=Available \
        deployment \
        --all \
        --timeout="${timeout}"; then

        error "ArgoCD deployments did not become ready within ${timeout}."

        echo
        error "Current ArgoCD pod status:"
        kubectl get pods -n "${ARGOCD_NAMESPACE}" -o wide

        echo
        error "Current ArgoCD deployment status:"
        kubectl get deployments -n "${ARGOCD_NAMESPACE}"

        echo
        error "Recent ArgoCD events:"
        kubectl get events \
            -n "${ARGOCD_NAMESPACE}" \
            --sort-by='.lastTimestamp' \
            | tail -20

        return 1
    fi

    success "All ArgoCD deployments are ready."

    info "Waiting for ArgoCD application controller..."

    if ! kubectl wait \
        --namespace "${ARGOCD_NAMESPACE}" \
        --for=jsonpath='{.status.readyReplicas}'=1 \
        statefulset/argocd-application-controller \
        --timeout="${timeout}"; then

        error "ArgoCD application controller did not become ready."

        kubectl get pods -n "${ARGOCD_NAMESPACE}" -o wide

        return 1
    fi

    success "ArgoCD application controller is ready."
}


verify_argocd_crds() {

    info "Verifying ArgoCD CRDs..."

    local crds=(
        "applications.argoproj.io"
        "appprojects.argoproj.io"
        "applicationsets.argoproj.io"
    )

    for crd in "${crds[@]}"; do

        if kubectl get crd "${crd}" >/dev/null 2>&1; then
            success "CRD available: ${crd}"
        else
            error "Required CRD is missing: ${crd}"
            return 1
        fi

    done
}


# ------------------------------------------------------------
# Initial admin password
# ------------------------------------------------------------

get_admin_password() {

    local secret_name="argocd-initial-admin-secret"

    info "Retrieving initial ArgoCD admin password..."

    if ! kubectl get secret "${secret_name}" \
        -n "${ARGOCD_NAMESPACE}" >/dev/null 2>&1; then

        error "ArgoCD initial admin secret was not found."
        return 1
    fi

    ARGOCD_ADMIN_PASSWORD="$(
        kubectl get secret "${secret_name}" \
            -n "${ARGOCD_NAMESPACE}" \
            -o jsonpath="{.data.password}" |
        base64 --decode
    )"

    if [[ -z "${ARGOCD_ADMIN_PASSWORD}" ]]; then
        error "ArgoCD admin password is empty."
        return 1
    fi
}


# ------------------------------------------------------------
# Port forwarding
# ------------------------------------------------------------

port_forward_running() {

    if [[ ! -f "${PORT_FORWARD_PID_FILE}" ]]; then
        return 1
    fi

    local pid

    pid="$(cat "${PORT_FORWARD_PID_FILE}")"

    if [[ -z "${pid}" ]]; then
        return 1
    fi

    if kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi

    rm -f "${PORT_FORWARD_PID_FILE}"

    return 1
}


start_port_forward() {

    if port_forward_running; then

        local existing_pid
        existing_pid="$(cat "${PORT_FORWARD_PID_FILE}")"

        success "ArgoCD port-forward already running (PID ${existing_pid})."
        return 0
    fi

    info "Starting ArgoCD port-forward..."

    mkdir -p "${STATE_DIR}"

    kubectl port-forward \
        -n "${ARGOCD_NAMESPACE}" \
        svc/argocd-server \
        "${ARGOCD_PORT}:443" \
        >"${PORT_FORWARD_LOG_FILE}" 2>&1 &

    local pid=$!

    echo "${pid}" > "${PORT_FORWARD_PID_FILE}"

    info "Port-forward process started with PID ${pid}."

    # Give kubectl a moment to establish the connection.
    sleep 2

    if ! kill -0 "${pid}" 2>/dev/null; then

        error "ArgoCD port-forward failed to start."

        if [[ -f "${PORT_FORWARD_LOG_FILE}" ]]; then
            cat "${PORT_FORWARD_LOG_FILE}"
        fi

        rm -f "${PORT_FORWARD_PID_FILE}"

        return 1
    fi

    success "ArgoCD UI port-forward is running."
}


# ------------------------------------------------------------
# Final output
# ------------------------------------------------------------

print_summary() {

    local context="kind-${CLUSTER_NAME}"

    echo
    echo "============================================================"
    echo "             ArgoCD Local Lab Ready"
    echo "============================================================"
    echo

    echo "Cluster:"
    echo "  Name:        ${CLUSTER_NAME}"
    echo "  Context:     ${context}"
    echo

    echo "Kubernetes:"
    kubectl version --output=json 2>/dev/null |
        grep -E '"gitVersion"' |
        head -2 || true

    echo

    echo "ArgoCD:"
    echo "  Version:     ${ARGOCD_VERSION}"
    echo "  Namespace:   ${ARGOCD_NAMESPACE}"
    echo

    echo "ArgoCD UI:"
    echo "  https://localhost:${ARGOCD_PORT}"
    echo

    echo "Credentials:"
    echo "  Username:    admin"
    echo "  Password:    ${ARGOCD_ADMIN_PASSWORD}"
    echo

    echo "Port-forward:"
    echo "  PID file:    ${PORT_FORWARD_PID_FILE}"
    echo "  Log file:    ${PORT_FORWARD_LOG_FILE}"
    echo

    echo "Useful commands:"
    echo
    echo "  kubectl get pods -n ${ARGOCD_NAMESPACE}"
    echo
    echo "  kubectl get applications -n ${ARGOCD_NAMESPACE}"
    echo
    echo "  argocd version"
    echo
    echo "  argocd app list"
    echo

    echo "To stop the port-forward:"
    echo
    echo "  kill \$(cat ${PORT_FORWARD_PID_FILE})"
    echo

    echo "============================================================"
}


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

main() {

    parse_args "$@"

    echo
    echo "============================================================"
    echo "              ArgoCD Local Lab Setup"
    echo "============================================================"
    echo

    info "Configuration:"
    echo "  Cluster name:       ${CLUSTER_NAME}"
    echo "  Kubernetes version: ${KUBERNETES_VERSION}"
    echo "  ArgoCD version:     ${ARGOCD_VERSION}"
    echo "  ArgoCD namespace:   ${ARGOCD_NAMESPACE}"
    echo "  ArgoCD port:        ${ARGOCD_PORT}"
    echo

    check_prerequisites
    check_docker

    create_kind_cluster
    configure_kubectl
    verify_cluster

    create_argocd_namespace
    install_argocd
    verify_argocd_crds
    wait_for_argocd

    get_admin_password
    start_port_forward

    print_summary
}


main "$@"
