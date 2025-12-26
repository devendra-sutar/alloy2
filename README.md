Onboarding Process Structure
Overview

This document describes the cluster onboarding process used to install monitoring, security, and observability tools on a Kubernetes cluster using a custom shell script packaged inside a Docker image referenced by a Helm chart.

We will cover:

Onboarding image and contents

Shell script structure and flow

How the onboarding Docker image is created

Helm chart for onboarding

Usage examples

📦 Onboarding Image
Image Name

os3infotech/monitoring-stack:v1.0.0

This image contains:

Kubernetes Event Exporter

Kubernetes Monitoring stack

Kepler

OpenCost

Alloy

Trivy Operator

Related metric tooling for CPU & memory dashboards

Additional tools — Kubearmor, Kyverno, and NFD — are bundled in the onboarding Helm chart (onboarding-agent) and not directly in this image.

Purpose

The image is responsible for:

Installing monitoring and security tools.

Reporting status back to a central API.

Running as a Kubernetes job via Helm.

🛠️ Shell Script (deploy.sh)

This script is packaged into the onboarding image and runs automatically when the image starts.

Script Goals

Validate tools and cluster state

Create Kubernetes accounts

Deploy monitoring/security tools

Send status updates to a central API

Produce a progress bar for status

⚙️ Key Features

Status Reporting

It reports cluster onboarding progress to a central API using JSON payloads.

REST endpoint:
POST https://<API_HOST>/api/v2.0/tools/installation/started

Uses curl to send updates like:

Tools Installation Started...

Tools Installation In Progress...

Tools Installation Failed...

Cluster Onboarded Successfully

📌 Script Configuration Variables
NAMESPACE="onboard"
OUTPUT_DIR="/tmp"
VALUES_TEMPLATE="values-template.yaml"
PARENT_CHART_NAME="onboarding-offline"

DEFAULT_OS_USERNAME="default-user"
DEFAULT_OS_PASSWORD="default-password"
DEFAULT_OS_HOST="https://10.0.33.244:9200"
DEFAULT_PROMETHEUS_HOST="http://10.0.2.13:9090"
DEFAULT_LOKI_HOST="http://10.0.2.13:3100"
DEFAULT_API_HOST="10.0.32.106:8006"


These variables can be overridden via Helm --set flags.
Script Flow Summary
Step 1 – Check Prerequisites

Ensure tools exist:

kubectl

helm

envsubst

curl

awk

Step 2 – ServiceAccount & ClusterRoleBinding

Creates:

Namespaced service account

ClusterRoleBinding with cluster-admin

kind: ServiceAccount ...
kind: ClusterRoleBinding ...

Step 3 – Namespace Conflict Check

Ensure no conflicts with:

alloy

kubesage-security

Step 4 – Create Event Exporter values-template.yaml

This file configures event exporter webhook connection.

It is then rendered with real variables using envsubst.

Step 5 – Render values.yml

Interpolates values with:

envsubst < values-template.yaml > values.yml

Step 6 – Deploy Kubernetes Event Exporter

Runs Helm to install event exporter with webhook config.

Step 7 – Deploy Monitoring Stack

Installs:

Prometheus

Grafana

Thanos

Node Exporters

Other exporters

This step includes checking CRDs and patching metadata.

Step 8 – Cost Analysis Stack

Deploys:

Kepler

OpenCost

Alloy

Configures remote write to central Prometheus.

helm upgrade --install kepler ...

Step 9 – Security Tools

Deploys Trivy Operator with metrics enabled.

Step 10 – Metrics Server

Applies Kubernetes metrics server manifest.

✅ Finalization

If everything succeeds:

log_success "Onboarding Completed Successfully!"

🧠 Flow High-Level Explanation

Status Reporting

Script sends cluster status to central API — visible in UI.

Foundation & Permissions

Creates service accounts and RBAC for tools.

Real-Time Events

Event Exporter watches Kubernetes events and POSTs them centrally.

Energy Monitoring

Kepler tracks hardware metrics via eBPF.

Cost Analysis

OpenCost computes pod-level costs.

Security

Trivy Operator scans images and exports metrics.

Aggregation

Alloy scrapes metrics and forwards them to central Prometheus.

Onboarding Image Creation

To build the Docker image:

Required Structure
.
├── Dockerfile
├── deploy.sh
├── charts/
├── manifests/

Inside /charts

Bundled offline .tgz charts:

alloy-0.1.1.tgz

kepler-0.6.1.tgz

kubernetes-event-exporter-3.6.3.tgz

node-feature-discovery-chart-0.18.3.tgz

k8s-monitoring-1.5.1.tgz

kubearmor-operator-v1.6.4.tgz

kyverno-3.2.6.tgz

opencost-2.4.1.tgz

Inside /manifests

components.yaml for metrics server

Dockerfile
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git gettext-base && ...

# Install kubectl
RUN curl -LO ... && chmod +x kubectl && mv kubectl /usr/local/bin/

# Install Helm
RUN curl https://raw.githubusercontent.com/.../get-helm-3 | bash

WORKDIR /app
COPY charts /app/charts
COPY manifests /app/manifests
COPY deploy.sh /app/deploy.sh

RUN chmod +x /app/deploy.sh

ENTRYPOINT ["/app/deploy.sh"]

Build & Push Image

Build:

docker build -t os3infotech/monitoring-stack:v1.0.0 .


Push to DockerHub.

📘 Onboarding Helm Chart
Directory Structure
onboarding-agent/
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

📄 Chart.yaml

Includes dependencies for:

Kyverno

KubeArmor

Node Feature Discovery

📄 Templates
_helpers.tpl

Validates required --set configurations.

sample-config.yaml

Default KubeArmorConfig.

onboarding.yaml

Contains:

onboarding service account

ConfigMap

Kubernetes job using the onboarding image

KubeSage agent service and deployment

🧪 Sample Helm Install Command
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

🧑‍💻 Agent Image (os3infotech/agent-stack:v1.0.0)
Dockerfile
FROM golang:1.24-alpine AS builder
...
RUN CGO_ENABLED=0 GOOS=linux go build ...

FROM alpine:3.20
COPY --from=builder /app/agent .
EXPOSE 9000
CMD ["./agent"]
