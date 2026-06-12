#!/usr/bin/env bash
# bootstrap-instance.sh — boot script for the SREGym "Pod Stuck Pending" demo EC2.
#
# Runs once on a fresh Amazon Linux 2023 instance. Idempotent: every step
# checks for prior completion, so re-running on a partially-set-up box
# converges to a healthy state.
#
# Sequence:
#   1. System packages (docker, git, kind, kubectl, helm, uvx, build deps)
#   2. SREGym checkout (provides MCP server image + manifests)
#   3. AURA binary (downloaded from S3 if available, otherwise built from source)
#   4. kind cluster up; SREGym MCP server applied
#   5. social-network workload deployed (Helm from SREGym-applications)
#   6. Port-forward mcp-server svc :9954; three fastmcp bridges :9961/:9962/:9964
#   7. Fault injection: scripts/inject-fault.sh assign_to_non_existent_node
#   8. aura-web-server on :8090, supervised by systemd
#
# Environment knobs (set in user-data wrapper or terraform.tfvars):
#   DEMO_S3_BUCKET     — S3 bucket holding pre-built artifacts (aura-web-server,
#                        SREGym tarball). Optional; if unset, we clone+build.
#   SREGYM_COMMIT_SHA  — Pinned SREGym commit. Default: main.
#   AURA_GIT_REF       — Pinned AURA ref. Default: main.
#   AURA_GIT_URL       — Repo URL. Default: git@github.com:mezmo/aura.git.
#                        Override to https://... if no deploy key configured.
#   BEDROCK_AWS_ACCESS_KEY_ID / BEDROCK_AWS_SECRET_ACCESS_KEY — cross-account
#                        Bedrock creds (Mezmo account 627029844476). Same pattern
#                        as the existing Bella Vista demo.

set -uxo pipefail
exec > >(tee -a /var/log/aura-demo-bootstrap.log) 2>&1

DEMO_ROOT=/opt/aura-demo
DEMO_USER=ec2-user
DEMO_HOME=/home/${DEMO_USER}

DEMO_S3_BUCKET="${DEMO_S3_BUCKET:-}"
SREGYM_COMMIT_SHA="${SREGYM_COMMIT_SHA:-main}"
AURA_GIT_REF="${AURA_GIT_REF:-main}"
AURA_GIT_URL="${AURA_GIT_URL:-https://github.com/mezmo/aura.git}"

# This script lives at <repo>/demo/sregym/scripts/bootstrap-instance.sh once
# distributed onto the instance. We resolve sibling scripts (inject-fault.sh,
# helpers under bin/) relative to it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_ASSETS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"   # demo/sregym/

log() { printf '[%(%FT%T%z)T bootstrap] %s\n' -1 "$*"; }
fail() { log "FATAL: $*"; exit 1; }

# ----------------------------------------------------------------------
# 1. System packages
# ----------------------------------------------------------------------
log "step 1: installing system packages"
if ! command -v docker >/dev/null 2>&1; then
  sudo dnf install -y docker git jq tar gzip make gcc gcc-c++ openssl-devel
  sudo systemctl enable --now docker
  sudo usermod -aG docker "${DEMO_USER}"
fi

if ! command -v kind >/dev/null 2>&1; then
  curl -sSL -o /tmp/kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind
fi

if ! command -v kubectl >/dev/null 2>&1; then
  curl -sSL -o /tmp/kubectl "https://dl.k8s.io/release/v1.30.0/bin/linux/amd64/kubectl"
  sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

if ! command -v helm >/dev/null 2>&1; then
  curl -sSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v uv >/dev/null 2>&1; then
  sudo -u "${DEMO_USER}" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi

# Rust only required if we have to build AURA from source (step 3 fallback).
# Defer the toolchain install to that branch — saves ~3 min on a happy boot.

# ----------------------------------------------------------------------
# 2. SREGym checkout
# ----------------------------------------------------------------------
log "step 2: SREGym checkout"
sudo mkdir -p "${DEMO_ROOT}"
sudo chown -R "${DEMO_USER}:${DEMO_USER}" "${DEMO_ROOT}"

if [ ! -d "${DEMO_ROOT}/SREGym/.git" ]; then
  if [ -n "${DEMO_S3_BUCKET}" ] && aws s3 ls "s3://${DEMO_S3_BUCKET}/staging/SREGym.tar.gz" >/dev/null 2>&1; then
    log "  pulling SREGym tarball from s3://${DEMO_S3_BUCKET}/staging/"
    aws s3 cp "s3://${DEMO_S3_BUCKET}/staging/SREGym.tar.gz" /tmp/SREGym.tar.gz
    sudo -u "${DEMO_USER}" tar -xzf /tmp/SREGym.tar.gz -C "${DEMO_ROOT}/"
    rm /tmp/SREGym.tar.gz
  else
    log "  cloning SREGym from GitHub"
    sudo -u "${DEMO_USER}" git clone --recurse-submodules \
      https://github.com/SREGym/SREGym "${DEMO_ROOT}/SREGym"
  fi
fi
sudo -u "${DEMO_USER}" git -C "${DEMO_ROOT}/SREGym" checkout "${SREGYM_COMMIT_SHA}"
sudo -u "${DEMO_USER}" git -C "${DEMO_ROOT}/SREGym" submodule update --init --recursive

# ----------------------------------------------------------------------
# 3. AURA binary
# ----------------------------------------------------------------------
log "step 3: AURA binary"
AURA_BIN="${DEMO_ROOT}/bin/aura-web-server"
sudo -u "${DEMO_USER}" mkdir -p "${DEMO_ROOT}/bin"

if [ ! -x "${AURA_BIN}" ]; then
  if [ -n "${DEMO_S3_BUCKET}" ] && aws s3 ls "s3://${DEMO_S3_BUCKET}/staging/aura-web-server" >/dev/null 2>&1; then
    log "  pulling pre-built aura-web-server from S3"
    sudo -u "${DEMO_USER}" aws s3 cp \
      "s3://${DEMO_S3_BUCKET}/staging/aura-web-server" "${AURA_BIN}"
    sudo chmod +x "${AURA_BIN}"
  else
    log "  building aura-web-server from source (${AURA_GIT_URL} @ ${AURA_GIT_REF})"
    if ! command -v cargo >/dev/null 2>&1; then
      sudo -u "${DEMO_USER}" bash -c \
        'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable'
    fi
    sudo -u "${DEMO_USER}" git clone "${AURA_GIT_URL}" "${DEMO_ROOT}/aura" || true
    sudo -u "${DEMO_USER}" git -C "${DEMO_ROOT}/aura" fetch origin "${AURA_GIT_REF}"
    sudo -u "${DEMO_USER}" git -C "${DEMO_ROOT}/aura" checkout "${AURA_GIT_REF}"
    sudo -u "${DEMO_USER}" bash -lc \
      "cd ${DEMO_ROOT}/aura && cargo build --release --bin aura-web-server"
    sudo cp "${DEMO_ROOT}/aura/target/release/aura-web-server" "${AURA_BIN}"
    sudo chmod +x "${AURA_BIN}"
  fi
fi
"${AURA_BIN}" --version || fail "aura-web-server smoke check failed"

# ----------------------------------------------------------------------
# 3b. aura-cli (operator-facing terminal client). Optional — the demo
#     works via curl without it, but the runbook uses aura-cli for a
#     rich TUI.
#
#     Source repo (answerbook/aura-cli) is private; we cannot clone it
#     on the EC2 without credentials. Install path:
#       1. If a pre-built Linux binary is in S3 staging, fetch it.
#       2. Otherwise, leave /usr/local/bin/aura-cli absent and rely on
#          the operator scp'ing it in (or curl-only walkthrough).
# ----------------------------------------------------------------------
if [ ! -x /usr/local/bin/aura-cli ]; then
  if [ -n "${DEMO_S3_BUCKET}" ] && aws s3 ls "s3://${DEMO_S3_BUCKET}/staging/aura-cli" >/dev/null 2>&1; then
    log "  pulling pre-built aura-cli from S3"
    sudo aws s3 cp "s3://${DEMO_S3_BUCKET}/staging/aura-cli" /usr/local/bin/aura-cli
    sudo chmod +x /usr/local/bin/aura-cli
    /usr/local/bin/aura-cli --version | head -1
  else
    log "  aura-cli not in S3 staging — leaving /usr/local/bin/aura-cli absent (demo works without it; scp it in for the rich TUI)"
  fi
fi

# ----------------------------------------------------------------------
# 4. kind cluster + SREGym MCP server
# ----------------------------------------------------------------------
log "step 4: kind cluster + SREGym MCP server"
export KUBECONFIG="${DEMO_HOME}/.kube/config"
sudo -u "${DEMO_USER}" mkdir -p "${DEMO_HOME}/.kube"

if ! sudo -u "${DEMO_USER}" kind get clusters 2>/dev/null | grep -q '^sregym$'; then
  # 4a. Build the SREGym MCP server image from the upstream checkout.
  # The image tag 'sregym:latest' is what mcp_server/k8s/*.yaml references.
  log "  building sregym:latest from SREGym/mcp_server/Dockerfile"
  # Build context must be the SREGym repo root — the Dockerfile COPYs
  # logger/ and other top-level dirs into the image, not just files
  # under mcp_server/.
  sudo docker build -t sregym:latest \
    -f "${DEMO_ROOT}/SREGym/mcp_server/Dockerfile" \
    "${DEMO_ROOT}/SREGym" 2>&1 | tail -10 \
    || fail "docker build of sregym:latest failed"

  # 4b. Create the kind cluster from SREGym's x86 config.
  log "  kind create cluster --name sregym"
  sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
    kind create cluster --name sregym \
      --config "${DEMO_ROOT}/SREGym/kind/kind-config-x86.yaml" \
      --kubeconfig "${KUBECONFIG}" \
    || fail "kind create cluster failed"

  # 4c. Bulk-load every image we'll need from the host docker cache into
  # the kind nodes' containerd, BEFORE applying Calico or the workload.
  # This is the speed win that lets fresh AMI launches finish bootstrap
  # in ~5 min instead of ~25 min — the host's /var/lib/docker has all
  # the images pre-pulled at AMI bake time, so kubelet finds them in
  # local containerd state and never reaches docker.io at deploy time.
  log "  kind load all pre-cached images from host docker"
  sudo -u "${DEMO_USER}" bash "${DEMO_ASSETS_DIR}/bin/aura-demo-kind-load-images" \
    || fail "kind load of pre-cached images failed"

  # 4d. Install a CNI. The AIOpsLab/SREGym kind image
  # (jacksonarthurclark/aiopslab-kind-x86) does NOT ship kindnet pre-baked,
  # so all nodes stay NotReady until we apply one. Calico is the canonical
  # choice for AIOpsLab-derived kind setups. Step 4c just loaded the
  # Calico images into kind, so this apply doesn't hit docker.io.
  log "  install Calico CNI (otherwise nodes stay NotReady forever)"
  sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml \
    || fail "kubectl apply of Calico manifest failed"

  log "  waiting up to 5 min for at least one node to become Ready"
  sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
    kubectl wait --for=condition=Ready node --all --timeout=300s \
    || fail "no node reached Ready within 5 min — check 'kubectl get pods -n kube-system'"

  # 4e. Apply the MCP server manifests (image was loaded in step 4c).
  log "  kubectl apply -k mcp_server/k8s"
  sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
    kubectl apply -k "${DEMO_ROOT}/SREGym/mcp_server/k8s/" \
    || fail "kubectl apply -k mcp_server/k8s failed"

  # 4f. Wait for mcp-server pod Running.
  log "  waiting for mcp-server pod Running (up to 5 min)"
  for i in $(seq 1 60); do
    PHASE=$(sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
      kubectl get pod -n sregym -l app.kubernetes.io/name=mcp-server \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
    if [ "${PHASE}" = "Running" ]; then
      log "  mcp-server Running after $((i * 5))s"
      break
    fi
    if [ "${i}" -eq 60 ]; then
      sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
        kubectl get pod -n sregym 2>&1 | head -5
      fail "mcp-server did not reach Running within 5 min"
    fi
    sleep 5
  done
fi

# kubeconfig was written by 'kind create' as root via the env-elevated
# sudo call above; on subsequent steps we read it as ec2-user (the
# DEMO_USER). Make sure ec2-user owns the dir + file.
sudo chown -R "${DEMO_USER}:${DEMO_USER}" "${DEMO_HOME}/.kube"

sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
  kubectl wait --for=condition=Ready node --all --timeout=300s

# ----------------------------------------------------------------------
# 5. social-network workload
# ----------------------------------------------------------------------
log "step 5: deploy social-network workload"
NS=social-network
if ! sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
     kubectl get ns "${NS}" >/dev/null 2>&1; then
  sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
    kubectl create namespace "${NS}"
fi

# SREGym-applications uses camelCase directory names; the actual chart for
# DeathStarBench social-network lives two levels deep at
# socialNetwork/helm-chart/socialnetwork/.
SN_CHART="${DEMO_ROOT}/SREGym/SREGym-applications/socialNetwork/helm-chart/socialnetwork"
if [ ! -f "${SN_CHART}/Chart.yaml" ]; then
  fail "social-network Helm chart not present at ${SN_CHART} (submodule init likely failed)"
fi

# The chart is heavyweight (~30 services, MongoDB + Redis + Memcached deps,
# all images pulled from docker.io). Give it a generous timeout; on a cold
# image cache this is 10-15 min easily on m5.xlarge.
sudo -u "${DEMO_USER}" env KUBECONFIG="${KUBECONFIG}" \
  helm upgrade --install social-network "${SN_CHART}" \
    --namespace "${NS}" \
    --timeout 20m \
    --wait

# ----------------------------------------------------------------------
# 6. port-forward mcp-server + start fastmcp bridges (as systemd services)
# ----------------------------------------------------------------------
log "step 6: port-forward + bridges (systemd)"

# 6a. kubectl port-forward as a systemd unit
sudo tee /etc/systemd/system/aura-demo-mcp-portforward.service >/dev/null <<UNIT
[Unit]
Description=AURA demo: port-forward SREGym mcp-server svc
After=network.target docker.service
Wants=docker.service

[Service]
User=${DEMO_USER}
Environment=KUBECONFIG=${KUBECONFIG}
# Wait until the mcp-server pod is actually Ready before opening the
# port-forward; this prevents the crashloop on AMI launch where kind
# containers come up but kubelet/pod recovery takes ~30s.
ExecStartPre=/usr/local/bin/kubectl wait --for=condition=Ready pod -n sregym -l app.kubernetes.io/name=mcp-server --timeout=300s
ExecStart=/usr/local/bin/kubectl port-forward svc/mcp-server -n sregym 9954:9954 --address 127.0.0.1
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT

# 6b. Three fastmcp bridges
for spec in "kubectl:9961" "jaeger:9962" "prometheus:9964"; do
  MOUNT="${spec%%:*}"
  PORT="${spec##*:}"
  sudo tee "/etc/systemd/system/aura-demo-bridge-${MOUNT}.service" >/dev/null <<UNIT
[Unit]
Description=AURA demo: fastmcp bridge for /${MOUNT} (Streamable HTTP on :${PORT})
After=aura-demo-mcp-portforward.service
Requires=aura-demo-mcp-portforward.service

[Service]
User=${DEMO_USER}
WorkingDirectory=${DEMO_HOME}
Environment=PATH=${DEMO_HOME}/.local/bin:/usr/local/bin:/usr/bin
ExecStart=${DEMO_HOME}/.local/bin/uvx --python 3.12 --from fastmcp[server] \\
  fastmcp run http://localhost:9954/${MOUNT}/sse \\
  --transport streamable-http --port ${PORT} --no-banner
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT
done

sudo systemctl daemon-reload
sudo systemctl enable --now aura-demo-mcp-portforward.service
sleep 3
for mount in kubectl jaeger prometheus; do
  sudo systemctl enable --now "aura-demo-bridge-${mount}.service"
  sudo systemctl restart "aura-demo-bridge-${mount}.service"
done

# ----------------------------------------------------------------------
# 7. Inject the fault
# ----------------------------------------------------------------------
log "step 7: inject assign_to_non_existent_node fault"
bash "${DEMO_ASSETS_DIR}/scripts/inject-fault.sh" assign_to_non_existent_node \
  || fail "fault injection failed"

# ----------------------------------------------------------------------
# 8. aura-web-server as systemd
# ----------------------------------------------------------------------
log "step 8: install aura-web-server systemd unit"

# Copy the demo TOML into a stable location.
sudo install -o "${DEMO_USER}" -g "${DEMO_USER}" -m 0644 \
  "${DEMO_ASSETS_DIR}/aura-sregym-demo.toml" \
  "${DEMO_ROOT}/aura-sregym-demo.toml"

# Bedrock cross-account creds: pulled from instance env (set by terraform
# user-data preamble that wraps this script).
sudo tee /etc/systemd/system/aura-demo-server.service >/dev/null <<UNIT
[Unit]
Description=AURA web-server for SREGym demo
After=aura-demo-bridge-kubectl.service aura-demo-bridge-jaeger.service aura-demo-bridge-prometheus.service
Requires=aura-demo-bridge-kubectl.service aura-demo-bridge-jaeger.service aura-demo-bridge-prometheus.service

[Service]
User=${DEMO_USER}
Environment=AWS_REGION=us-east-1
Environment=AWS_DEFAULT_REGION=us-east-1
EnvironmentFile=-/etc/aura-demo.env
Environment=AURA_CUSTOM_EVENTS=true
Environment=TOOL_RESULT_MODE=aura
Environment=CONFIG_PATH=${DEMO_ROOT}/aura-sregym-demo.toml
Environment=HOST=127.0.0.1
Environment=PORT=8090
ExecStart=${AURA_BIN}
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
UNIT

# /etc/aura-demo.env holds Bedrock creds. If terraform user-data populated
# this before running us, the systemd unit picks it up. Otherwise fall back
# to whatever's in this script's env (e.g. for manual reruns).
if [ ! -f /etc/aura-demo.env ] && [ -n "${BEDROCK_AWS_ACCESS_KEY_ID:-}" ]; then
  sudo tee /etc/aura-demo.env >/dev/null <<EOF
AWS_ACCESS_KEY_ID=${BEDROCK_AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${BEDROCK_AWS_SECRET_ACCESS_KEY}
EOF
  sudo chmod 600 /etc/aura-demo.env
fi

sudo systemctl daemon-reload
sudo systemctl enable --now aura-demo-server.service
# enable --now does NOT restart an already-running unit; force a restart so
# a re-run of bootstrap (after editing the unit) actually picks up changes.
sudo systemctl restart aura-demo-server.service

# ----------------------------------------------------------------------
# 9. Convenience: drop helper bins onto PATH + status sentinel
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# 8b. AMI-firstboot cleanup unit. When this AMI is launched on a fresh
#     EC2, the kind cluster auto-resumes but etcd holds pod entries
#     whose containerd state has been GC'd in the worker nodes; those
#     pods show up as 'Unknown' and never recover until kubectl force-
#     deletes them so the deployment controllers schedule fresh ones.
#     This oneshot unit does that automatically on every boot.
# ----------------------------------------------------------------------
log "step 8b: install AMI-firstboot cleanup oneshot"
# Install the standalone cleanup script (lives in bin/ — keeps the
# systemd unit's ExecStart trivial, avoiding escape-layer issues with
# inline awk that we hit on the first iteration of this design).
sudo install -m 0755 "${DEMO_ASSETS_DIR}/bin/aura-demo-cleanup-unknown" \
  /usr/local/bin/aura-demo-cleanup-unknown

sudo tee /etc/systemd/system/aura-demo-firstboot.service >/dev/null <<UNIT
[Unit]
Description=AURA demo: clean up Unknown pods from AMI etcd state
After=aura-demo-mcp-portforward.service
Requires=aura-demo-mcp-portforward.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aura-demo-cleanup-unknown
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable aura-demo-firstboot.service
# Trigger now if the cluster has Unknown pods at this point (idempotent;
# the oneshot exits cleanly when there are none).
sudo systemctl restart aura-demo-firstboot.service || true

log "step 9: install helper bins"
for helper in sregym-status sregym-ask aura-demo-kind-load-images aura-demo-cleanup-unknown; do
  if [ -x "${DEMO_ASSETS_DIR}/bin/${helper}" ]; then
    sudo install -m 0755 "${DEMO_ASSETS_DIR}/bin/${helper}" "/usr/local/bin/${helper}"
  fi
done
for helper in inject-fault.sh reset-fault.sh; do
  if [ -x "${DEMO_ASSETS_DIR}/scripts/${helper}" ]; then
    sudo install -m 0755 "${DEMO_ASSETS_DIR}/scripts/${helper}" "/usr/local/bin/${helper}"
  fi
done

log "boot complete"
echo "ready" | sudo tee /var/log/aura-demo-bootstrap.ready >/dev/null
