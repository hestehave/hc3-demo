#!/usr/bin/env bash
# Helper commands for the HC3 "Break it on purpose" demo.
# Usage: ./demo.sh <command>
set -uo pipefail
NS=vmlab
APPS_DOMAIN=apps.cluster-5cz6g.dyn.redhatworkshops.io
URL="http://web-${NS}.${APPS_DOMAIN}/"
KEY="${HC3_KEY:-$HOME/.ssh/hc3demo}"

case "${1:-}" in
  traffic)   # Pane B: which backend answers, twice a second
    while true; do
      printf '%s  ' "$(date +%T)"
      curl -s -m 2 "$URL" || echo "--- no response ---"
      sleep 0.5
    done ;;
  pool)      # Pane C: the web tier, VMs and containers in one list (no 'watch' needed on macOS)
    while true; do
      out="$(oc get pods -n $NS -l tier=web --sort-by=.metadata.name \
        -o custom-columns='NAME:.metadata.name,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName,IP:.status.podIP' 2>&1)"
      clear; echo "web tier  ($(date +%T))"; echo; echo "$out"
      sleep 2
    done ;;
  rogue)     # Pane B during step 1: can the rogue pod reach the database?
    oc exec -n $NS rogue -- bash -c 'while true; do
      if timeout 1 bash -c "</dev/tcp/db/5432" 2>/dev/null; then
        echo "$(date +%T)  rogue -> db:5432   OPEN   <<< EXPOSED"
      else
        echo "$(date +%T)  rogue -> db:5432   blocked"
      fi; sleep 1; done' ;;
  open-fw)   # Step 1: the "2 a.m. troubleshooting" change, made by hand
    oc patch networkpolicy web-to-db -n $NS --type=json \
      -p '[{"op":"replace","path":"/spec/ingress/0/from","value":[{"podSelector":{}}]}]' ;;
  kill-vm)   # Step 2
    oc delete vm web3 -n $NS --wait=false ;;
  kill-app)  # Step 3: stop the web server inside web2
    virtctl ssh "fedora@vmi/web2" -n $NS -i "$KEY" \
      --local-ssh-opts="-o StrictHostKeyChecking=no" --local-ssh-opts="-o UserKnownHostsFile=/dev/null" \
      -c 'sudo systemctl stop webdemo && echo "webdemo stopped on $(hostname)"' ;;
  refresh)   # Step 4: make Argo CD read Git now instead of waiting for its poll
    oc annotate application vmlab -n openshift-gitops argocd.argoproj.io/refresh=normal --overwrite ;;
  status)    # Pre-flight
    oc get application vmlab -n openshift-gitops -o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status'
    oc get vm,vmi -n $NS
    oc get networkpolicy -n $NS
    curl -s -m 3 "$URL" || echo "route not answering" ;;
  *) echo "commands: traffic | pool | rogue | open-fw | kill-vm | kill-app | refresh | status" ;;
esac
