#!/usr/bin/env bash
# inject-fault.sh — apply a named SREGym fault to the deployed workload.
#
# Usage:
#   inject-fault.sh <problem-name> [<deployment>] [<namespace>]
#
# Currently supported:
#   assign_to_non_existent_node — adds a nodeSelector that no node matches,
#                                 so the deployment's pods stay Pending.
#
# Defaults target the social-network workload's user-service deployment.

set -euo pipefail

PROBLEM="${1:-}"
TARGET_DEPLOY="${2:-user-service}"
NS="${3:-social-network}"
KUBECONFIG="${KUBECONFIG:-/home/ec2-user/.kube/config}"
export KUBECONFIG

if [ -z "${PROBLEM}" ]; then
  echo "usage: $(basename "$0") <problem-name> [<deployment>] [<namespace>]" >&2
  exit 2
fi

if ! kubectl get ns "${NS}" >/dev/null 2>&1; then
  echo "namespace ${NS} not found — has the workload been deployed?" >&2
  exit 1
fi

if ! kubectl get deployment/"${TARGET_DEPLOY}" -n "${NS}" >/dev/null 2>&1; then
  echo "deployment/${TARGET_DEPLOY} not found in namespace ${NS}" >&2
  echo "available deployments:" >&2
  kubectl get deployment -n "${NS}" -o name >&2
  exit 1
fi

case "${PROBLEM}" in
  assign_to_non_existent_node)
    echo "[inject] patching deployment/${TARGET_DEPLOY} in namespace ${NS}:"
    echo "         nodeSelector.nodename = aura-demo-nonexistent-node"
    kubectl patch deployment/"${TARGET_DEPLOY}" -n "${NS}" \
      --type=strategic \
      --patch '{"spec":{"template":{"spec":{"nodeSelector":{"nodename":"aura-demo-nonexistent-node"}}}}}'

    echo "[inject] waiting up to 60s for at least one pod to enter Pending..."
    for _ in $(seq 1 30); do
      STATE=$(kubectl get pods -n "${NS}" \
        -l app="${TARGET_DEPLOY}" \
        -o jsonpath='{.items[*].status.phase}' 2>/dev/null || true)
      if echo "${STATE}" | grep -qw Pending; then
        echo "[inject] confirmed Pending pod present"
        break
      fi
      sleep 2
    done

    echo
    echo "[inject] post-injection pod state:"
    kubectl get pods -n "${NS}" -l app="${TARGET_DEPLOY}" -o wide || true
    echo
    echo "[inject] use 'kubectl describe pod -n ${NS} -l app=${TARGET_DEPLOY}' to see"
    echo "         the FailedScheduling event AURA will key off of."
    ;;
  *)
    echo "unknown problem '${PROBLEM}'" >&2
    echo "supported problems: assign_to_non_existent_node" >&2
    exit 2
    ;;
esac
