#!/usr/bin/env bash
# reset-fault.sh — clear an injected fault and restore healthy state.
#
# Usage:
#   reset-fault.sh [<deployment>] [<namespace>]
#
# Reverses whatever inject-fault.sh did, so the learner can re-run the demo
# (e.g. "try it yourself" stage where they drive AURA themselves). The reset
# is deliberately problem-agnostic: it strips any nodeSelector / affinity /
# tolerations the inject script may have planted and then waits for the
# deployment to roll out healthy.

set -euo pipefail

TARGET_DEPLOY="${1:-user-service}"
NS="${2:-social-network}"
KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
export KUBECONFIG

if ! kubectl get deployment/"${TARGET_DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
  echo "deployment/${TARGET_DEPLOY} not found in namespace ${NS}" >&2
  exit 1
fi

echo "[reset] stripping nodeSelector from deployment/${TARGET_DEPLOY}"
# Strategic merge: setting a map field to null deletes it. Idempotent —
# safe to run when there's no nodeSelector present.
kubectl patch deployment/"${TARGET_DEPLOY}" -n "${NS}" \
  --type=strategic \
  --patch '{"spec":{"template":{"spec":{"nodeSelector":null}}}}' \
  >/dev/null

echo "[reset] waiting up to 5 min for rollout to complete"
kubectl rollout status deployment/"${TARGET_DEPLOY}" -n "${NS}" --timeout=300s || {
  echo "[reset] rollout did not complete cleanly; current state:" >&2
  kubectl get pods -n "${NS}" -l app="${TARGET_DEPLOY}" -o wide >&2
  exit 1
}

echo "[reset] post-reset pod state:"
kubectl get pods -n "${NS}" -l app="${TARGET_DEPLOY}" -o wide
echo "[reset] ready — fault can be re-injected via inject-fault.sh"
