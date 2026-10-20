#!/usr/bin/env bash
# Renders the four VM manifests from templates/vm.yaml.tpl.
# Usage: ./render.sh ~/.ssh/hc3demo.pub
# Portable: works with macOS (BSD) awk and Linux (GNU) awk. Values are passed
# through the environment, because BSD awk rejects multi-line -v values.
set -euo pipefail
cd "$(dirname "$0")"

PUBKEY_FILE="${1:?usage: ./render.sh <path-to-ssh-public-key>}"
export R_KEY="$(cat "$PUBKEY_FILE")"

WEB_PROBES='      readinessProbe:
        httpGet: {port: 8080, path: /}
        initialDelaySeconds: 20
        periodSeconds: 5
        failureThreshold: 2
      livenessProbe:
        httpGet: {port: 8080, path: /}
        initialDelaySeconds: 300
        periodSeconds: 10
        failureThreshold: 3'

# Scheduler rule: prefer to keep web VMs on different nodes (soft rule, never blocks scheduling)
WEB_AFFINITY='      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  tier: web
              topologyKey: kubernetes.io/hostname'

render() { # name tier port probes affinity
  local out="manifests/$1.yaml" tmp
  tmp="$(mktemp)"
  R_NAME="$1" R_TIER="$2" R_PORT="$3" R_PROBES="$4" R_AFFINITY="$5" awk '
    BEGIN { name = ENVIRON["R_NAME"]; tier = ENVIRON["R_TIER"]; port = ENVIRON["R_PORT"]
            key = ENVIRON["R_KEY"]; probes = ENVIRON["R_PROBES"]; affinity = ENVIRON["R_AFFINITY"] }
    /^__PROBES__$/   { if (probes != "") print probes; next }
    /^__AFFINITY__$/ { if (affinity != "") print affinity; next }
    { line = $0
      while ((i = index(line, "__NAME__")) > 0)       line = substr(line, 1, i-1) name substr(line, i+8)
      while ((i = index(line, "__TIER__")) > 0)       line = substr(line, 1, i-1) tier substr(line, i+8)
      while ((i = index(line, "__PORT__")) > 0)       line = substr(line, 1, i-1) port substr(line, i+8)
      while ((i = index(line, "__SSH_PUBKEY__")) > 0) line = substr(line, 1, i-1) key  substr(line, i+14)
      print line }' templates/vm.yaml.tpl > "$tmp"
  mv "$tmp" "$out"
  echo "wrote $out"
}

render web1 web 8080 "$WEB_PROBES" "$WEB_AFFINITY"
render web2 web 8080 "$WEB_PROBES" "$WEB_AFFINITY"
render web3 web 8080 "$WEB_PROBES" "$WEB_AFFINITY"
render db   db  5432 "" ""
