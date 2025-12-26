# Onboarding Process Structure

This document outlines the structure and process for the Onboarding Agent, covering the Docker images, shell scripts, Helm charts, and installation flows.

## 1. Onboarding Image

**Image Name:** `os3infotech/monitoring-stack:v1.0.0`

This image is responsible for installing and configuring the following tools:
*   Kubernetes Event Exporter
*   K8s Monitoring
*   Kepler
*   OpenCost
*   Alloy
*   Trivy Operator
*   Metrics Server (via `components.yaml`)

**Note:** Kubearmor, Kyverno, and NFD are NOT installed by this image; they are dependencies of the `onboarding-agent` Helm chart itself.

### Shell Script (`deploy.sh`)

The core of the onboarding image is a shell script that orchestrates the deployment. It determines the flow and logic for installing tools using the offline charts bundled in the image.

```bash
#!/usr/bin/env bash
# Robust Kubernetes Deployment Script (Final Version)
set -euo pipefail

### ===== Configuration Variables =====
NAMESPACE="onboard"
OUTPUT_DIR="/tmp"
VALUES_TEMPLATE="values-template.yaml"
PARENT_CHART_NAME="onboarding-offline"
DEFAULT_OS_USERNAME="default-user"
DEFAULT_OS_PASSWORD="default-password"
DEFAULT_OS_HOST="https://10.0.33.244:9200"
DEFAULT_PROMETHEUS_HOST="http://10.0.2.13:9090"
DEFAULT_LOKI_HOST="http://10.0.2.13:3100"
DEFAULT_API_HOST="10.0.32.106:8006" # host:port only

### ===== Colors =====
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

### ===== Logging =====
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_success(){ echo -e "${GREEN}[SUCCESS]${NC} $*"; }

### ===== Progress Bar =====
TOTAL_STEPS=10
CURRENT_STEP=0
show_progress(){
  local percent=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
  local bar_width=50
  local filled=$(( percent * bar_width / 100 ))
  local empty=$(( bar_width - filled ))
  printf "\r["
  printf "%0.s#" $(seq 1 $filled)
  printf "%0.s-" $(seq 1 $empty)
  printf "] %3d%%" "$percent"
  if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
    echo
  fi
}

### ===== Send Status Update (POST JSON) =====
send_status(){
  local status_msg="$1"
  local payload="{\"cluster_name\":\"${CLUSTER_NAME}\",\"status\":\"${status_msg}\"}"
  
  if [[ -z "${API_URL:-}" ]]; then
    # If API_URL is strictly required, you might want to exit here too.
    # Currently keeping this as warn for configuration safety, 
    # but the CALL failure below is now a hard stop.
    log_warn "API_URL not set — skipping status update: ${status_msg}"
    return 0
  fi
  
  log_info "Sending status to API: ${status_msg}"
  
  # Try ONCE, timeout 5s, continue if fail
  http_code=$(curl -k -m 5 --silent --write-out "%{http_code}" \
    --output /tmp/api_resp.json \
    -H "Content-Type: application/json" \
    -d "${payload}" \
    "${API_URL}" || echo "000")
    
  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    log_success "Status sent: ${status_msg}"
  else
    # === CHANGED: STOP SCRIPT IF API FAILS ===
    log_error "API failed (HTTP=${http_code}). Stopping installation because API update is mandatory."
    exit 1
  fi
  return 0
}

### ===== Utilities =====
retry_cmd(){
  local attempts="${1:-3}"; shift
  local sleep_seconds="${1:-2}"; shift
  local i=0
  until "$@"; do
    i=$((i+1))
    if [ "$i" -ge "$attempts" ]; then
      log_error "Command failed after ${attempts} attempts: $*"
      return 1
    fi
    local backoff=$(( sleep_seconds * (2 ** (i - 1)) ))
    log_warn "Retry ${i}/${attempts} in ${backoff}s..."
    sleep "$backoff"
  done
  return 0
}

### ===== TRAP: Ensure failure status is sent on any error/exit =====
INSTALLATION_SUCCEEDED=false
cleanup_on_failure() {
  if [[ "$INSTALLATION_SUCCEEDED" == "false" ]]; then
    # Note: If API is down, this call will also fail and exit the trap.
    send_status "Tools Installation Failed..." || true
  fi
}
trap cleanup_on_failure EXIT

### ===== Usage =====
show_usage(){
  cat <<EOF
Usage: $0 <CLUSTER_NAME> [USERNAME] [PROMETHEUS_URL] [LOKI_URL] [API_HOST] [AGENT_ID] [API_KEY] [OPTIONS]
Required:
  CLUSTER_NAME Cluster identifier
Optional:
  USERNAME (default: admin-user)
  PROMETHEUS_URL (default: $DEFAULT_PROMETHEUS_HOST)
  LOKI_URL (default: $DEFAULT_LOKI_HOST)
  API_HOST (default: $DEFAULT_API_HOST)
  AGENT_ID (default: empty)
  API_KEY  (default: empty)
Options:
  --os-username USER --os-password PASS --os-host URL
  -n/--namespace NS
  --values-template FILE
  --dry-run --skip-monitoring --skip-trivy
EOF
  exit 0
}

### ===== Parse Positional Args (Updated) =====
CLUSTER_NAME="${1:-}"; shift || true
USERNAME="${1:-admin-user}"; shift || true
PROMETHEUS_HOST="${1:-$DEFAULT_PROMETHEUS_HOST}"; shift || true
LOKI_HOST="${1:-$DEFAULT_LOKI_HOST}"; shift || true
API_HOST="${1:-$DEFAULT_API_HOST}"; shift || true
AGENT_ID="${1:-}"; shift || true  # New Argument 6
API_KEY="${1:-}"; shift || true   # New Argument 7

### ===== Named Args =====
SKIP_EVENT_EXPORTER=false
DRY_RUN=false
SKIP_MONITORING=false
SKIP_TRIVY=false
SKIP_COST_ANALYSIS=false
OS_USERNAME="$DEFAULT_OS_USERNAME"
OS_PASSWORD="$DEFAULT_OS_PASSWORD"
OS_HOST="$DEFAULT_OS_HOST"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os-username) OS_USERNAME="${2:-}"; shift 2;;
    --os-password) OS_PASSWORD="${2:-}"; shift 2;;
    --os-host) OS_HOST="${2:-}"; shift 2;;
    -n|--namespace) NAMESPACE="${2:-$NAMESPACE}"; shift 2;;
    --values-template) VALUES_TEMPLATE="${2:-$VALUES_TEMPLATE}"; shift 2;;
    --skip-monitoring) SKIP_MONITORING=true; shift;;
    --skip-trivy) SKIP_TRIVY=true; shift;;
    --dry-run) DRY_RUN=true; shift;;
    -h|--help) show_usage;;
    *) log_error "Unknown: $1"; show_usage;;
  esac
done

### ===== API URL & Webhook Normalize =====
API_PATH="/api/v2.0/tools/installation/started"
WEBHOOK_PATH="/webhook/incidents"

_is_url() { [[ "$1" =~ ^https?:// ]]; }
_is_host_or_hostport() { [[ "$1" =~ ^[0-9A-Za-z.-]+(:[0-9]+)?$ ]]; }

WEBHOOK_ENDPOINT=""

if [[ -z "$API_HOST" ]]; then
  unset API_URL
else
  if _is_url "$API_HOST"; then
    # It is a full URL (e.g., ashish.kubesage.ai -> https://ashish.kubesage.ai)
    API_HOST="${API_HOST%/}" # Remove trailing slash
    API_URL="${API_HOST}${API_PATH}"
    WEBHOOK_ENDPOINT="${API_HOST}${WEBHOOK_PATH}"
  elif _is_host_or_hostport "$API_HOST"; then
    # It is just host:port (e.g., 10.0.32.106:8006 -> https://10.0.32.106:8006)
    API_URL="https://${API_HOST}${API_PATH}"
    WEBHOOK_ENDPOINT="https://${API_HOST}${WEBHOOK_PATH}"
  else
    log_error "Invalid API_HOST: ${API_HOST}"
    unset API_URL
  fi
fi

log_info "Resolved API URL: ${API_URL:-<none>}"
log_info "Resolved Webhook Endpoint: ${WEBHOOK_ENDPOINT:-<none>}"

### ===== Validate Required =====
if [[ -z "${CLUSTER_NAME:-}" ]]; then
  log_error "CLUSTER_NAME is required"
  exit 1
fi

### ===== Sanitize SA =====
SA_NAME=$(echo "$USERNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9.-]/-/g')
if ! [[ "$SA_NAME" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  log_error "Invalid SA name: $SA_NAME"
  send_status "Tools Installation Failed..."
  exit 1
fi

### ===== Pre-checks =====
log_info "Checking output dir writability..."
if touch "${OUTPUT_DIR}/test" &>/dev/null && rm -f "${OUTPUT_DIR}/test"; then
  log_success "${OUTPUT_DIR} writable"
else
  log_error "${OUTPUT_DIR} not writable"
  send_status "Tools Installation Failed..."
  exit 1
fi

send_status "Tools Installation Started..."

### Step 1: Prereqs
log_info "Checking required tools: kubectl, helm, envsubst, curl, awk"
for tool in kubectl helm envsubst curl awk; do
  if ! command -v "$tool" >/dev/null; then
    log_error "Missing tool: $tool"
    send_status "Tools Installation Failed..."
    exit 1
  fi
done
log_success "Tools ready"
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### Step 2: ServiceAccount + ClusterRoleBinding
retry_cmd 3 2 kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
EOF
log_success "ServiceAccount + ClusterRoleBinding created"
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### Step 3: Namespace conflict check
for ns in alloy kubesage-security; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    log_error "Namespace '$ns' exists. Cannot proceed."
    send_status "Tools Installation Failed..."
    exit 1
  fi
done
log_success "No conflicting namespaces"
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### Step 4: Values template (Event Exporter Default)
log_info "Creating values template..."
cat > "${OUTPUT_DIR}/${VALUES_TEMPLATE}" <<'EOF'
config:
  clusterName: "${CLUSTER_NAME}"
  leaderElection: {}
  logFormat: json
  logLevel: debug
  maxEventAgeSeconds: 60
  receivers:
    - name: "webhook-receiver"
      webhook:
        endpoint: "${WEBHOOK_ENDPOINT}"
        tls:
          insecureSkipVerify: true
        headers:
          X-Cluster-Name: "${CLUSTER_NAME}"
          X-Agent-ID: "${AGENT_ID}"
          X-API-Key: "${API_KEY}"
        layout:
          eventType: kubernetes-event
          metadata:
            creationTimestamp: "{{ .CreationTimestamp }}"
            name: "{{ .Name }}"
            namespace: "{{ .InvolvedObject.Namespace }}"
            resource: "{{ .ResourceVersion }}"
            uid: "{{ .UID }}"
          reason: "{{ .Reason }}"
          message: "{{ .Message }}"
          type: "{{ .Type }}"
          clusterName: "{{ .ClusterName }}"
          source:
            component: "{{ .Source.Component }}"
            host: "{{ .Source.Host }}"
          firstTimestamp: "{{ .FirstTimestamp }}"
          lastTimestamp: "{{ .LastTimestamp }}"
          involvedObject:
            kind: "{{ .InvolvedObject.Kind }}"
            name: "{{ .InvolvedObject.Name }}"
            namespace: "{{ .InvolvedObject.Namespace }}"
            apiVersion: "{{ .InvolvedObject.APIVersion }}"
            resourceVersion: "{{ .InvolvedObject.ResourceVersion }}"
            uid: "{{ .InvolvedObject.UID }}"
            labels: "{{ .InvolvedObject.Labels | toJson }}"
            annotations: "{{ .InvolvedObject.Annotations | toJson }}"
  route:
    routes:
      - drop:
        - namespace: "event-exporter"
        - type: "Normal"
      - match:
        - receiver: "webhook-receiver"
EOF
log_success "Values template created"
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress
send_status "Tools Installation In Progress..."

### Step 5: Render values
log_info "Rendering values template..."
export OS_USERNAME OS_PASSWORD OS_HOST CLUSTER_NAME SA_NAME
envsubst < "${OUTPUT_DIR}/${VALUES_TEMPLATE}" > "${OUTPUT_DIR}/values.yml" || {
  log_error "envsubst failed"
  send_status "Tools Installation Failed..."
  exit 1
}
if [[ ! -s "${OUTPUT_DIR}/values.yml" ]]; then
  log_error "Rendered values.yml is empty"
  send_status "Tools Installation Failed..."
  exit 1
fi
log_success "Values rendered"
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### Step 6: Event Exporter (Updated with Webhook)
deploy_event_exporter(){
  if [[ "$SKIP_EVENT_EXPORTER" == "true" ]]; then
    log_warn "Skipping event exporter"
    return 0
  fi
  log_info "Deploying Kubernetes Event Exporter..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run: skipping install of event exporter"
    return 0
  fi
  
  # Note: This overwrites the 'dump' receiver (index 0) defined in values.yml
  # with the Webhook config.
  retry_cmd 3 2 helm upgrade --install kubernetes-event-exporter \
    ./charts/kubernetes-event-exporter-3.6.3.tgz \
    --create-namespace -n "$NAMESPACE" \
    -f "${OUTPUT_DIR}/values.yml" \
    --set image.repository=bitnamilegacy/kubernetes-event-exporter  
  log_success "Event Exporter deployed"
}
deploy_event_exporter
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress
send_status "Monitoring Tools Installation In Progress..."

### Step 7: Monitoring Stack
if [[ "$SKIP_MONITORING" != "true" ]]; then
  log_info "Deploying monitoring stack…"
  RELEASE_NAME="my-release"
  TARGET_NS="$NAMESPACE"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run: skipping monitoring stack"
  else
    # 1. CRD CHECK & PATCH
    CRD_LIST=(
      servicemonitors.monitoring.coreos.com
      prometheuses.monitoring.coreos.com
      alertmanagers.monitoring.coreos.com
      prometheusrules.monitoring.coreos.com
      podmonitors.monitoring.coreos.com
      probes.monitoring.coreos.com
      thanosrulers.monitoring.coreos.com
      alertmanagerconfigs.monitoring.coreos.com
      prometheusagents.monitoring.coreos.com
      scrapeconfigs.monitoring.coreos.com
    )
    missing_crd=false
    need_patch=false

    for crd in "${CRD_LIST[@]}"; do
      if ! kubectl get crd "$crd" &>/dev/null; then
        log_warn "CRD missing: $crd"
        missing_crd=true
      else
        managed_by=$(kubectl get crd "$crd" -o jsonpath='{.metadata.labels.app.kubernetes.io/managed-by}' 2>/dev/null || echo "")
        ann_name=$(kubectl get crd "$crd" -o jsonpath='{.metadata.annotations.meta.helm.sh/release-name}' 2>/dev/null || echo "")
        ann_ns=$(kubectl get crd "$crd" -o jsonpath='{.metadata.annotations.meta.helm.sh/release-namespace}' 2>/dev/null || echo "")

        if [[ "$managed_by" != "Helm" || "$ann_name" != "$RELEASE_NAME" || "$ann_ns" != "$TARGET_NS" ]]; then
          log_warn "CRD $crd exists but lacks Helm ownership metadata — will patch"
          need_patch=true
        fi
      fi
    done

    # 2. INSTALL CRDS IF MISSING
    if [[ "$missing_crd" = true ]]; then
      log_info "Some CRDs missing — installing CRDs first..."
      helm install monitoring-crds ./charts/k8s-monitoring-1.5.1.tgz \
           -n "$TARGET_NS" --create-namespace \
           --skip-crds=false \
           --set cluster.name="$CLUSTER_NAME" \
           --set grafana.enabled=false \
           --set prometheus.enabled=false \
           --set alertmanager.enabled=false \
           --timeout 300s || log_warn "CRD install attempt failed — continuing"

      # Wait for registration
      for i in {1..10}; do
        all_exist=true
        for crd in "${CRD_LIST[@]}"; do
          if ! kubectl get crd "$crd" &>/dev/null; then all_exist=false; break; fi
        done
        if $all_exist; then break; fi
        sleep 3
      done
    fi

    # 3. PATCH EXISTING CRDS
    if [[ "$need_patch" = true ]]; then
      log_info "Patching existing CRDs..."
      for crd in "${CRD_LIST[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
          kubectl label crd "$crd" app.kubernetes.io/managed-by=Helm --overwrite
          kubectl annotate crd "$crd" meta.helm.sh/release-name="$RELEASE_NAME" --overwrite
          kubectl annotate crd "$crd" meta.helm.sh/release-namespace="$TARGET_NS" --overwrite
        fi
      done
    fi

    # 4. MAIN INSTALLATION
    retry_cmd 3 2 helm upgrade --install "$RELEASE_NAME" ./charts/k8s-monitoring-1.5.1.tgz \
           -n "$TARGET_NS" --create-namespace \
           --skip-crds \
           --set opencost.enabled=false \
           --set cluster.name="$CLUSTER_NAME" \
           --set externalServices.prometheus.host="$PROMETHEUS_HOST" \
           --set externalServices.prometheus.writeEndpoint=/api/v1/write \
           --set externalServices.prometheus.externalLabels.username="$SA_NAME" \
           --set externalServices.loki.host="$LOKI_HOST" \
           --set grafana.enabled=true
  fi
  log_success "Monitoring stack deployed"
else
  log_info "Monitoring stack skipped"
fi
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### Step 8: Cost Analysis
if [[ "$SKIP_COST_ANALYSIS" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run: skipping cost analysis"
  else
    log_info "Deploying cost analysis..."
    retry_cmd 3 2 helm upgrade --install kepler ./charts/kepler-0.6.1.tgz -n "$NAMESPACE"
    retry_cmd 3 2 helm upgrade --install opencost ./charts/opencost-2.4.1.tgz -n "$NAMESPACE"
    
    retry_cmd 3 2 kubectl patch deployment opencost -n "$NAMESPACE" --type='json' \
      -p='[{"op":"replace","path":"/spec/template/spec/containers/0/env","value":[{"name":"PROMETHEUS_SERVER_ENDPOINT","value":"'"$PROMETHEUS_HOST"'"},{"name":"INSECURE_SKIP_VERIFY","value":"true"}]}]'
    
    kubectl -n onboard set env deployment/opencost CUSTOM_PRICING_ENABLED=true || true
    kubectl -n onboard set env deployment/opencost CLOUD_COST_ENABLED=true || true
    
    cat > "${OUTPUT_DIR}/config.alloy" <<EOF
prometheus.scrape "opencost" {
  targets = [{"__address__" = "opencost.${NAMESPACE}.svc.cluster.local:9003"}]
  scrape_interval = "1m"
  metrics_path = "/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
}
prometheus.scrape "kepler" {
  targets = [{"__address__" = "kepler.${NAMESPACE}.svc.cluster.local:9102"}]
  scrape_interval = "1m"
  metrics_path = "/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
}
prometheus.scrape "trivy_operator" {
  targets = [{"__address__" = "trivy-operator.${NAMESPACE}.svc.cluster.local:80"}]
  scrape_interval = "1m"
  metrics_path = "/metrics"
  forward_to = [prometheus.remote_write.central.receiver]
}
prometheus.remote_write "central" {
  endpoint {
    url = "${PROMETHEUS_HOST}/api/v1/write"
    tls_config {
      insecure_skip_verify = true
    }
  }
  external_labels = { cluster = "${CLUSTER_NAME}", username = "${SA_NAME}" }
}
EOF
    kubectl create configmap alloy-config --namespace "$NAMESPACE" --from-file=config.alloy="${OUTPUT_DIR}/config.alloy" --dry-run=client -o yaml | kubectl apply -f -
    
    cat > "${OUTPUT_DIR}/values-alloy.yaml" <<EOF
alloy:
  configMap:
    create: false
    name: alloy-config
    key: config.alloy
EOF
    retry_cmd 3 2 helm upgrade --install alloy ./charts/alloy-0.1.1.tgz -n "$NAMESPACE" -f "${OUTPUT_DIR}/values-alloy.yaml"
    log_success "Cost analysis deployed"
  fi
else
  log_info "Skipping cost analysis"
fi
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress
send_status "Security Tools Installation In Progress..."

### Step 9: Trivy Operator (Online Fetch & Conflict Free)
send_status "Security Tools Installation In Progress..."

if [[ "$SKIP_TRIVY" != "true" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry-run: skipping Trivy Operator"
  else
    log_info "Deploying Trivy Operator (Online)..."

    # 1. CLEANUP OLD INSTALLATION (Optional but safe)
    helm uninstall trivy-operator -n "$NAMESPACE" 2>/dev/null || true

    # 2. CLEANUP CONFLICTING CRDS (Critical for upgrades/re-installs)
    log_info "Cleaning up conflicting CRDs..."
    kubectl delete crd clustercompliancereports.aquasecurity.github.io --ignore-not-found=true
    kubectl delete crd vulnerabilityreports.aquasecurity.github.io --ignore-not-found=true
    kubectl delete crd configauditreports.aquasecurity.github.io --ignore-not-found=true
    kubectl delete crd infraassessmentreports.aquasecurity.github.io --ignore-not-found=true
    kubectl delete crd sbomreports.aquasecurity.github.io --ignore-not-found=true
    kubectl delete crd clustersbomreports.aquasecurity.github.io --ignore-not-found=true
    
    # 3. CONFIGURATION
    cat > "${OUTPUT_DIR}/trivy-values.yaml" <<EOF
operator:
  metricsVulnIdEnabled: true
serviceMonitor:
  enabled: true
trivy:
  ignoreUnfixed: true
service:
  headless: false
EOF

    # 4. ADD REPO & INSTALL (Online)
    log_info "Adding Aqua Security Helm repo..."
    retry_cmd 3 2 helm repo add aquasecurity https://aquasecurity.github.io/helm-charts
    retry_cmd 3 2 helm repo update

    log_info "Installing Chart from repo..."
    retry_cmd 3 2 helm upgrade --install trivy-operator aquasecurity/trivy-operator \
      -n "$NAMESPACE" \
      -f "${OUTPUT_DIR}/trivy-values.yaml"
    log_success "Trivy Operator deployed successfully from online repo."
  fi
else
  log_info "Skipping Trivy Operator"
fi

CURRENT_STEP=$((CURRENT_STEP+1)); show_progress
send_status "Cluster Onboarded Successfully"

### Step 10: Metrics Server
if [[ "$DRY_RUN" != "true" ]]; then
  log_info "Deploying Metrics Server..."
  kubectl apply -f ./manifests/components.yaml
  kubectl patch deployment metrics-server -n kube-system --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' || true
  log_success "Metrics Server applied"
else
  log_info "Dry-run: skipping Metrics Server"
fi
CURRENT_STEP=$((CURRENT_STEP+1)); show_progress

### ===== Final Success =====
INSTALLATION_SUCCEEDED=true
log_success "Onboarding Completed Successfully!"
exit 0
```

### Script Flow

1.  **Installation Lifecycle & Status Reporting**: Tracks progress and reports status (Started, Failed, Completed) to the `API_HOST`. Stops if the API is unreachable.
2.  **Foundation & Access Control**: Creates a `ServiceAccount` and binds it to `cluster-admin`.
3.  **Real-Time Incident Tracking**: Deploys **Kubernetes Event Exporter** to listen for events and push them to a Webhook URL.
4.  **Energy Monitoring**: Deploys **Kepler** (DaemonSet with eBPF) to measure energy consumption, exposing metrics on port 9102.
5.  **Cost Analysis**: Deploys **OpenCost** to map resource usage to costs, exposing metrics on port 9003.
6.  **Security Scanning**: Deploys **Trivy Operator** to scan for vulnerabilities, exposing metrics on port 80 (with `metricsVulnIdEnabled`).
7.  **Central Aggregation (Alloy)**: Deploys **Grafana Alloy** as the shipping agent. It scrapes metrics from Kepler, OpenCost, and Trivy, then forwards them to Central Prometheus via `remote_write`.

### Docker Image Creation

The image `os3infotech/monitoring-stack:v1.0.0` is built with an offline bundle of Helm charts to ensure internet-independence during the specific tool installation phase.

**IMPORTANT: Pre-requisite Directory Structure**

Before building the image, you must have the following directories and files **in the same folder**:
```
.
├── Dockerfile
├── deploy.sh
├── charts/              # Directory where .tgz chart files will be placed
└── manifests/           # Directory where component.yaml will be placed
```

**Build Process Steps:**

1.  **Populate `charts/` directory**:
    You must assume the `charts` folder is populated with the required helm charts (e.g., `kepler-0.6.1.tgz`, `alloy-0.1.1.tgz`).
    *   Command: `helm pull <chart-repo>/<chart-name> --version <version>`
    *   Example: `helm pull kepler/kepler --version 0.6.1`
    *   Repeat for all tools: Alloy, Kepler, K8s Event Exporter, K8s Monitoring, Opencost, Trivy, etc.

2.  **Populate `manifests/` directory**:
    Download the `components.yaml` for Metrics Server.
    *   Command: `wget -O manifests/components.yaml https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`

3.  **Build and Push the Image**:
    Once the folders are populated, build the Docker image.
    *   Command: `docker build -t os3infotech/monitoring-stack:v1.0.0 .`
    *   Command: `docker push os3infotech/monitoring-stack:v1.0.0`

**Dockerfile:**
```dockerfile
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Install kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/

# Install Helm
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

WORKDIR /app

# Copy Artifacts
# This assumes 'charts' and 'manifests' directories are already populated locally
COPY charts /app/charts
COPY manifests /app/manifests
COPY deploy.sh /app/deploy.sh

RUN chmod +x /app/deploy.sh

ENTRYPOINT ["/app/deploy.sh"]
```
*Note: The `charts` and `manifests` folders are copied directly into the image, allowing the `deploy.sh` script to install tools without internet access.*

## 2. Onboarding Helm Chart

**Chart Name:** `onboarding-agent`
**Version:** `0.1.1`

This chart orchestrates the deployment of the onboarding job (which runs the Monitoring Stack) AND installs the Agent Stack.

**Chart Directory Structure:**
```
onboarding-agent/
├── Chart.lock
├── Chart.yaml
├── charts/
│   ├── kubearmor-operator-v1.6.4.tgz
│   ├── kyverno-3.2.6.tgz
│   └── node-feature-discovery-chart-0.18.3.tgz
├── templates/
│   ├── _helpers.tpl
│   ├── onboarding.yaml
│   └── sample-config.yaml
└── values.yaml
```

**Dependencies (Chart.yaml):**
The chart defines dependencies for KubeArmor, Kyverno, and NFD. These are bundled into the chart's own `charts/` directory when running `helm dependency build`.

```yaml
apiVersion: v2
name: onboarding-agent
description: A Helm chart for Kubernetes
type: application
version: 0.1.1
appVersion: "1.16.0"
dependencies:
  - name: kyverno
    version: 3.2.6
    repository: https://kyverno.github.io/kyverno/
    condition: kyverno.enabled
  - name: kubearmor-operator
    version: 1.6.4
    repository: https://kubearmor.github.io/charts
    condition: kubearmor.enabled
  - name: node-feature-discovery
    version: 0.18.3
    repository: https://kubernetes-sigs.github.io/node-feature-discovery/charts
    condition: nfd.enabled
```

### Templates

**`templates/_helpers.tpl`**:
Validates that all required values (`clusterName`, `username`, `prometheusUrl`, `lokiUrl`, `backendHost`, `providerName`, `agentId`, `apiKey`, `tags`) are provided.

**`templates/sample-config.yaml`**:
Defines a default `KubeArmorConfig` to set security posture (e.g., `defaultFilePosture: audit`).

**`templates/onboarding.yaml`**:
Creates the following resources:
1.  **ServiceAccount & Role (`onboarding-sa`)**: For the onboarding job.
2.  **Job (`k8s-onboarding-job`)**: Runs the `os3infotech/monitoring-stack:v1.0.0` image with arguments derived from Helm values.
3.  **ServiceAccount & Role (`kubesage-agent`)**: For the Agent.
4.  **Deployment (`my-agent`)**: Deploys the `os3infotech/agent-stack:v1.0.0` image.
    *   Exposes Port 9000.
    *   Uses `agent-env` ConfigMap.

## 3. Agent Image (`os3infotech/agent-stack:v1.0.0`)

The agent is built from a Go binary and packaged in a lightweight Alpine image.

**Dockerfile:**
```dockerfile
# ============== Stage 1: Build ==============
FROM golang:1.24-alpine AS builder

# Install git (in case of private modules)
RUN apk add --no-cache git

WORKDIR /app

# Copy go module files
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build static binary
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w -extldflags '-static'" \
    -o agent .

# ============== Stage 2: Runtime ==============
FROM alpine:3.20

# Install ca-certificates (needed for HTTPS, even with SKIP_TLS_VERIFY)
RUN apk add --no-cache ca-certificates

WORKDIR /app

# Copy binary
COPY --from=builder /app/agent .

# Copy .env file (will be overridden by ConfigMap at runtime)
COPY .env .

# Expose port
EXPOSE 9000

# Run
CMD ["./agent"]
```

## 4. Installation

The `onboarding-agent` Helm chart is hosted on GitHub Pages. You can install it using the following command:

```bash
helm repo add onboarding-chart-repo https://OS3Infotech.github.io/KubeSage-Public/ && \
helm repo update && \
helm install onboarding-release onboarding-chart-repo/onboarding-agent \
  --namespace onboard --create-namespace \
  --set clusterName="test-cluster" \
  --set username="admin" \
  --set prometheusUrl="https://testing-dev.kubesage.ai/prometheus" \
  --set lokiUrl="https://testing-dev.kubesage.ai/loki" \
  --set backendHost="testing-dev.kubesage.ai" \
  --set providerName="AWS EKS" \
  --set tags="{}" \
  --set agentId="851108b0-f358-4ad5-a268-897a9b882aa8" \
  --set apiKey="ks_U7YDllxRjFbdDUG16qyrdYrjyEnrG2oB"
```
