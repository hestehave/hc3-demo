#!/usr/bin/env bash
# "Break it on purpose" - the whole demo in one terminal window.
#
#   ./breakit.sh check     pre-flight: everything green? (run 15 min before you go on)
#   ./breakit.sh           run the demo
#   ./breakit.sh 3         start at step 3
#   ./breakit.sh reset     put things back after a rehearsal
#
# At each step: SPACE (or any key) types the command and runs it.
#   s = skip this step   n = next step   r = run without typing   q = quit
# While a live view is running: any key ends it early.
# Works with the bash 3.2 that ships with macOS. Needs: oc, virtctl, curl.

set -uo pipefail
cd "$(dirname "$0")"

NS=vmlab
APPS_DOMAIN=apps.cluster-5cz6g.dyn.redhatworkshops.io
URL="http://web-${NS}.${APPS_DOMAIN}/"
KEY="${HC3_KEY:-$HOME/.ssh/hc3demo}"
TYPE_DELAY="${TYPE_DELAY:-0.03}"

if [ -t 1 ]; then
  C_DESC=$'\033[1;36m'; C_NOTE=$'\033[2;37m'; C_CMD=$'\033[1;37m'; C_PROMPT=$'\033[1;32m'
  C_HEAD=$'\033[1;41;37m'; C_OK=$'\033[1;32m'; C_BAD=$'\033[1;31m'; C_WARN=$'\033[1;33m'; C_OFF=$'\033[0m'
else
  C_DESC=; C_NOTE=; C_CMD=; C_PROMPT=; C_HEAD=; C_OK=; C_BAD=; C_WARN=; C_OFF=
fi

# ---------------- small helpers (also usable as typed commands) ----------------
hit()      { curl -s -m 2 "$URL" 2>/dev/null | head -1; }
rogue_db() { oc exec -n "$NS" rogue -- timeout 1 bash -c '</dev/tcp/db/5432' >/dev/null 2>&1 && echo OPEN || echo blocked; }
webvms()   { oc get vmi -n "$NS" -l tier=web --no-headers \
               -o custom-columns='N:.metadata.name,P:.status.phase,R:.status.conditions[?(@.type=="Ready")].status,NODE:.status.nodeName' 2>/dev/null \
             | awk '{printf "%s:%s%s ", $1, ($3=="True"?"ready":"NOT-READY"), ($4!=""?"@"$4:"")}'; }
vssh()     { virtctl ssh "fedora@vmi/$1" -n "$NS" -i "$KEY" \
               --local-ssh-opts="-o StrictHostKeyChecking=no" --local-ssh-opts="-o UserKnownHostsFile=/dev/null" \
               --local-ssh-opts="-o LogLevel=ERROR" -c "$2"; }

# Wait up to $1 seconds, but return at once on a key press (returns 0 if a key was pressed)
pause_or_key() { local k; IFS= read -rsn1 -t "$1" k </dev/tty && return 0 || return 1; }

# ---------------- live views (run until done, or a key press) ----------------
watch_firewall() {   # rogue -> db, until it has been OPEN and is blocked again
  local seen_open=0 r i
  echo "${C_NOTE}  (live: can the rogue pod reach the database? any key to stop)${C_OFF}"
  for i in $(seq 1 40); do
    r=$(rogue_db)
    if [ "$r" = OPEN ]; then seen_open=1; echo "  $(date +%T)  rogue -> db:5432   ${C_BAD}OPEN  <<< EXPOSED${C_OFF}"
    else echo "  $(date +%T)  rogue -> db:5432   ${C_OK}blocked${C_OFF}"; fi
    if [ $seen_open = 1 ] && [ "$r" = blocked ]; then
      echo "${C_OK}  Healed: Argo CD put the rule back.${C_OFF}"; return 0; fi
    pause_or_key 1 && return 0
  done
}

watch_traffic() {    # $1 = seconds, $2 = stop when this text answers (optional)
  local max="$1" want="${2:-}" start now ans vms gone=0
  start=$(date +%s)
  echo "${C_NOTE}  (live: who answers the load balancer, and the state of the web VMs; any key to stop)${C_OFF}"
  while :; do
    now=$(date +%s); [ $((now - start)) -ge "$max" ] && break
    ans=$(hit); [ -z "$ans" ] && ans="${C_BAD}-- no answer --${C_OFF}"
    vms=$(webvms)
    printf '  %s  %-26s  %s\n' "$(date +%T)" "$ans" "${C_NOTE}${vms}${C_OFF}"
    # finished only after the VM has first dropped out (not ready or gone) and then answers again
    if [ -n "$want" ] && ! echo "$vms" | grep -q "$want:ready"; then gone=1; fi
    if [ -n "$want" ] && [ $gone = 1 ] && echo "$ans" | grep -q "$want"; then
      echo "${C_OK}  $want is back in the pool.${C_OFF}"; return 0; fi
    pause_or_key 1 && return 0
  done
}

# ---------------- presentation engine ----------------
START="${1:-1}"; CUR=0; SKIP=0
key() { local k; IFS= read -rsn1 k </dev/tty; [ "$k" = q ] && { echo; exit 0; }; KP="$k"; }
on()  { [ "$CUR" -ge "$START" ] && [ "$SKIP" -eq 0 ]; }
chapter() {
  CUR="$1"; SKIP=0; on || return 0
  clear; echo; printf '%s\n' "${C_HEAD}  $1 · $2  ${C_OFF}"
  [ -n "${3:-}" ] && printf '%s\n' "${C_NOTE}  Say: $3${C_OFF}"; echo
}
step() {  # step <description> <command>
  on || return 0
  local d="$1" c="$2" i
  echo; printf '%s\n' "${C_DESC}# $d${C_OFF}"; key
  case "$KP" in s) echo "${C_NOTE}  (skipped)${C_OFF}"; return 0;; n) SKIP=1; return 0;; esac
  printf '%s' "${C_PROMPT}\$ ${C_OFF}${C_CMD}"
  if [ "$KP" = r ]; then printf '%s' "$c"; else
    for ((i = 0; i < ${#c}; i++)); do printf '%s' "${c:i:1}"; sleep "$TYPE_DELAY"; done; fi
  printf '%s\n' "$C_OFF"
  eval "$c"
}
live() { on || return 0; eval "$1"; }   # untyped live view after a step

# ---------------- check / reset ----------------
ok()  { echo "  ${C_OK}OK${C_OFF}    $1"; }
bad() { echo "  ${C_BAD}FIX${C_OFF}   $1"; FAIL=1; }
if [ "${1:-}" = check ]; then
  FAIL=0; echo "Pre-flight for the Break it on purpose demo"
  oc whoami >/dev/null 2>&1 && ok "logged in as $(oc whoami)" || { bad "not logged in: oc login ..."; exit 1; }
  s=$(oc get application vmlab -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  [ "$s" = "Synced/Healthy" ] && ok "Argo CD app: $s" || bad "Argo CD app is '$s' (open Argo CD, press Refresh then Sync)"
  n=$(oc get vmi -n "$NS" --no-headers 2>/dev/null | grep -c Running); [ "$n" = 4 ] && ok "4 VMs running" || bad "$n of 4 VMs running (oc get vm -n $NS)"
  w=$(webvms); echo "$w" | grep -q NOT-READY && bad "a web VM is not ready: $w (./breakit.sh reset)" || ok "web VMs ready: $w"
  young=$(oc get vmi -n "$NS" -l tier=web -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null \
    | while IFS== read -r name ts; do
        t=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || date -u -d "$ts" +%s 2>/dev/null || echo 0)
        [ $(( $(date +%s) - t )) -lt 150 ] && echo "$name"; done)
  [ -z "$young" ] && ok "web VMs up long enough for the health checks" || bad "wait 2-3 minutes, just started: $young"
  a=$(hit); [ -n "$a" ] && ok "load balancer answers: $a" || bad "the Route doesn't answer ($URL)"
  oc get pod rogue -n "$NS" >/dev/null 2>&1 && ok "rogue pod present" || bad "rogue pod missing: oc apply -f ops/rogue.yaml"
  [ "$(rogue_db)" = blocked ] && ok "rogue -> db is blocked" || bad "rogue can reach db: Argo CD should heal it; check the app"
  np=$(oc get networkpolicy -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' '); [ "$np" = 3 ] && ok "3 network policies" || bad "$np network policies (expected 3)"
  [ -f "$KEY" ] && ok "SSH key $KEY" || bad "SSH key $KEY missing (step 3 needs it)"
  echo; [ $FAIL = 0 ] && echo "${C_OK}All green. Run: ./breakit.sh${C_OFF}" || echo "${C_WARN}Fix the FIX lines, then run check again.${C_OFF}"
  exit $FAIL
fi
if [ "${1:-}" = reset ]; then
  echo "Resetting after a rehearsal"
  oc annotate application vmlab -n openshift-gitops argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  for vm in web1 web2 web3; do
    r=$(oc get vmi "$vm" -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    [ "$r" = True ] || { echo "  restarting $vm"; virtctl restart "$vm" -n "$NS" >/dev/null 2>&1 || true; }
  done
  echo "Wait about 3 minutes, then run: ./breakit.sh check"
  exit 0
fi
case "$START" in [1-4]) ;; *) echo "usage: ./breakit.sh [check | reset | <step 1-4>]"; exit 1;; esac

# =====================================================================
#  The demo
# =====================================================================
chapter 1 "The shop, running from Git" \
  "Three web VMs, a database VM, a load balancer and a firewall. All of it is in Git, and Argo CD keeps the cluster equal to Git."
step "The VMs: three web servers and a database, spread across the nodes." \
     "oc get vmi -n $NS -o wide"
step "The load balancer answers from all three web VMs in turn." \
     "for i in 1 2 3 4 5 6; do hit; sleep 0.5; done"
step "The firewall: three policies, all by label. A rogue pod must never reach the database." \
     "oc get networkpolicy -n $NS && rogue_db"

chapter 2 "Someone opens the firewall" \
  "It's 2 a.m., someone is troubleshooting, and they open the database rule to everything."
step "Open the database firewall rule to every pod, by hand." \
     "oc patch networkpolicy web-to-db -n $NS --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/ingress/0/from\",\"value\":[{\"podSelector\":{}}]}]'"
live "watch_firewall"
step "The rule is back exactly as Git says: only the web tier." \
     "oc get networkpolicy web-to-db -n $NS -o jsonpath='{.spec.ingress[0].from}{\"\\n\"}'"
on && echo "${C_NOTE}  Say: Nobody reverted it. In the old world that click becomes the truth until an audit finds it.${C_OFF}"

chapter 3 "Someone deletes a VM" \
  "web3 is gone, disk and all. Watch the traffic: no outage, and watch web3 come back."
step "Delete web3." \
     "oc delete vm web3 -n $NS --wait=false"
live "watch_traffic 240 'web3'"
on && echo "${C_NOTE}  Say: Rebuilt from the golden image, back in the pool when healthy. The VM, its pool membership and its firewall rules are one definition.${C_OFF}"

chapter 4 "The app dies, the VM looks fine" \
  "The VM is up, the hypervisor would call it healthy, but the web server inside is dead."
step "Stop the web server inside web2." \
     "vssh web2 'sudo systemctl stop webdemo && echo webdemo stopped on \$(hostname)'"
live "watch_traffic 240 'web2'"
on && echo "${C_NOTE}  Say: Readiness took it out of the load balancer, liveness restarted the VM. No ticket, no page.${C_OFF}"

on && { echo; echo "${C_HEAD}  Done · back to the slides  ${C_OFF}"; }
