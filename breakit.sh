#!/usr/bin/env bash
# "Break it on purpose" - the whole demo in one terminal window.
#
#   ./breakit.sh check     pre-flight: everything green? (run 15 min before you go on)
#   ./breakit.sh           run the demo
#   ./breakit.sh 3         start at step 3
#   ./breakit.sh reset     put things back after a rehearsal
#
# At each step: SPACE (or any key) types the command and runs it.
#   s = skip this step   n = next chapter   r = run without typing   q = quit
# While a live view is running: any key ends it early.
# Between chapters the script waits for a key, so you can talk over the result.
# Every typed command is a real command you could paste yourself.
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

# The real commands the demo types (kept here so the live views use the same ones)
SSH_OPTS="--local-ssh-opts=-oStrictHostKeyChecking=no --local-ssh-opts=-oUserKnownHostsFile=/dev/null --local-ssh-opts=-oLogLevel=ERROR"
ROGUE_TEST="oc exec rogue -n $NS -- timeout 1 bash -c '</dev/tcp/db/5432' 2>/dev/null && echo OPEN || echo blocked"

# ---------------- helpers for the live views and the check (never typed) ----------------
hit()      { curl -s -m 2 "$URL" 2>/dev/null | head -1; }
rogue_db() { eval "$ROGUE_TEST"; }
db_rule()  {   # what the web-to-db rule lets in: web | ANY | ?
  local f; f=$(oc get networkpolicy web-to-db -n "$NS" -o jsonpath='{.spec.ingress[0].from}' 2>/dev/null)
  if [ -z "$f" ]; then echo "?"; elif echo "$f" | grep -q '"tier":"web"'; then echo web; else echo ANY; fi; }
webvms()   { oc get vmi -n "$NS" -l tier=web --no-headers \
               -o custom-columns='N:.metadata.name,P:.status.phase,R:.status.conditions[?(@.type=="Ready")].status,NODE:.status.nodeName' 2>/dev/null \
             | awk '{printf "%s:%s%s ", $1, ($3=="True"?"ready":"NOT-READY"), ($4!=""?"@"$4:"")}'; }

# Wait up to $1 whole seconds (bash 3.2), return 0 at once on a key press
pause_or_key() { local k; IFS= read -rsn1 -t "$1" k </dev/tty && return 0 || return 1; }

# ---------------- live views (run until done, or a key press) ----------------
watch_firewall() {   # until the rule has been opened and Argo CD has put it back
  local seen_open=0 i rule r rt ct
  echo "${C_NOTE}  (live: what the database rule allows, and whether the rogue pod gets in; any key to stop)${C_OFF}"
  for i in $(seq 1 90); do
    rule=$(db_rule); r=$(rogue_db)
    case "$rule" in
      ANY) seen_open=1; rt="${C_BAD}ANY pod    ${C_OFF}";;
      web) rt="${C_OK}tier=web   ${C_OFF}";;
      *)   rt="${C_WARN}?          ${C_OFF}";;
    esac
    if [ "$r" = OPEN ]; then seen_open=1; ct="${C_BAD}OPEN  <<< EXPOSED${C_OFF}"; else ct="${C_OK}blocked${C_OFF}"; fi
    echo "  $(date +%T)  rule allows: $rt  rogue -> db:5432  $ct"
    if [ $seen_open = 1 ] && [ "$rule" = web ] && [ "$r" = blocked ]; then
      echo "${C_OK}  Healed: Argo CD put the rule back the way Git says.${C_OFF}"; return 0; fi
    pause_or_key 1 && return 0
  done
  echo "${C_WARN}  Not healed after 90 s: open Argo CD and press Refresh.${C_OFF}"
}

watch_traffic() {    # $1 = seconds, $2 = stop when this VM answers again (optional)
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
START="${1:-1}"; CUR=0; SKIP=0; SHOWN=0
key() { local k; IFS= read -rsn1 k </dev/tty; [ "$k" = q ] && { echo; exit 0; }; KP="$k"; }
on()  { [ "$CUR" -ge "$START" ] && [ "$SKIP" -eq 0 ]; }
say() { on && printf '\n%s\n' "${C_NOTE}  Say: $1${C_OFF}"; return 0; }
chapter() {
  local was_skipped=$SKIP
  CUR="$1"; SKIP=0; on || return 0
  # Keep the last result on screen until the presenter is ready to move on
  if [ $SHOWN = 1 ] && [ $was_skipped = 0 ]; then
    printf '\n%s' "${C_NOTE}  ── next: $1 · $2  (any key) ──${C_OFF}"; key; fi
  SHOWN=1
  clear; echo; printf '%s\n' "${C_HEAD}  $1 · $2  ${C_OFF}"
  [ -n "${3:-}" ] && printf '%s\n' "${C_NOTE}  Say: $3${C_OFF}"; echo
}
step() {  # step <description> <command>
  on || return 0
  local d="$1" c="$2" i delay="$TYPE_DELAY"
  [ ${#c} -gt 90 ] && delay=0.01        # type long commands faster
  echo; printf '%s\n' "${C_DESC}# $d${C_OFF}"; key
  case "$KP" in s) echo "${C_NOTE}  (skipped)${C_OFF}"; return 0;; n) SKIP=1; return 0;; esac
  printf '%s' "${C_PROMPT}\$ ${C_OFF}${C_CMD}"
  if [ "$KP" = r ]; then printf '%s' "$c"; else
    for ((i = 0; i < ${#c}; i++)); do printf '%s' "${c:i:1}"; sleep "$delay"; done; fi
  printf '%s\n' "$C_OFF"
  eval "$c"
}
live() { on || return 0; eval "$1"; }   # untyped live view right after a step

# ---------------- check / reset ----------------
ok()  { echo "  ${C_OK}OK${C_OFF}    $1"; }
bad() { echo "  ${C_BAD}FIX${C_OFF}   $1"; FAIL=1; }
if [ "${1:-}" = check ]; then
  FAIL=0; echo "Pre-flight for the Break it on purpose demo"
  oc whoami >/dev/null 2>&1 && ok "logged in as $(oc whoami)" || { bad "not logged in: oc login ..."; exit 1; }
  command -v virtctl >/dev/null && ok "virtctl found" || bad "virtctl not in PATH (step 4 needs it)"
  s=$(oc get application vmlab -n openshift-gitops -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  [ "$s" = "Synced/Healthy" ] && ok "Argo CD app: $s" || bad "Argo CD app is '$s' (open Argo CD, press Refresh then Sync)"
  n=$(oc get vmi -n "$NS" --no-headers 2>/dev/null | grep -c Running); [ "$n" = 4 ] && ok "4 VMs running" || bad "$n of 4 VMs running (oc get vm -n $NS)"
  w=$(webvms); echo "$w" | grep -q NOT-READY && bad "a web VM is not ready: $w (./breakit.sh reset)" || ok "web VMs ready: $w"
  young=$(oc get vmi -n "$NS" -l tier=web -o jsonpath='{range .items[*]}{.metadata.name}={.metadata.creationTimestamp}{"\n"}{end}' 2>/dev/null \
    | while IFS== read -r name ts; do
        t=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || date -u -d "$ts" +%s 2>/dev/null || echo 0)
        [ $(( $(date +%s) - t )) -lt 330 ] && echo "$name"; done)
  [ -z "$young" ] && ok "web VMs up 6+ minutes: health checks armed" || bad "wait until 6 minutes after start (step 4 needs the liveness check armed): $young"
  a=$(hit); [ -n "$a" ] && ok "load balancer answers: $a" || bad "the Route doesn't answer ($URL)"
  if oc exec rogue -n "$NS" -- true >/dev/null 2>&1; then ok "rogue pod present and running"
  else bad "rogue pod missing or not running: oc apply -f ops/rogue.yaml"; fi
  [ "$(db_rule)" = web ] && ok "database rule allows tier=web only" || bad "database rule is '$(db_rule)': Argo CD should heal it; check the app"
  [ "$(rogue_db)" = blocked ] && ok "rogue -> db is blocked" || bad "rogue can reach db: Argo CD should heal it; check the app"
  np=$(oc get networkpolicy -n "$NS" --no-headers 2>/dev/null | wc -l | tr -d ' '); [ "$np" = 3 ] && ok "3 network policies" || bad "$np network policies (expected 3)"
  if [ ! -f "$KEY" ]; then bad "SSH key $KEY missing (step 4 needs it)"
  elif eval "virtctl ssh fedora@vmi/web2 -n $NS -i $KEY $SSH_OPTS --local-ssh-opts=-oConnectTimeout=10 -c 'systemctl is-active webdemo'" 2>/dev/null | grep -q '^active'; then
    ok "SSH into web2 works, web server active"
  else bad "SSH into web2 failed (step 4 needs it): virtctl ssh fedora@vmi/web2 -n $NS -i $KEY"; fi
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
  echo "Wait about 6 minutes, then run: ./breakit.sh check"
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
     "for i in 1 2 3 4 5 6; do curl -s $URL; sleep 0.5; done"
step "The firewall: three policies, all by label." \
     "oc get networkpolicy -n $NS"
step "A pod that is not part of the app tries the database port. It must be blocked." \
     "$ROGUE_TEST"

chapter 2 "Someone opens the firewall" \
  "It's 2 a.m., someone is troubleshooting, and they open the database rule to every pod."
step "Open the database rule to every pod, by hand, then watch." \
     "oc patch networkpolicy web-to-db -n $NS --type=json -p '[{\"op\":\"replace\",\"path\":\"/spec/ingress/0/from\",\"value\":[{\"podSelector\":{}}]}]'"
live "watch_firewall"
step "The rule is back exactly as Git says: only the web tier." \
     "oc get networkpolicy web-to-db -n $NS -o jsonpath='{.spec.ingress[0].from}{\"\\n\"}'"
step "Who put it back? Argo CD, automatically, seconds after the change." \
     "oc get application vmlab -n openshift-gitops -o jsonpath='{.status.operationState.operation.initiatedBy}  {.status.operationState.finishedAt}{\"\\n\"}'"
say "Nobody reverted it by hand. In the old world that change becomes the truth until an audit finds it."

chapter 3 "Someone deletes a VM" \
  "web3 is gone, disk and all. Watch the traffic: no outage, and watch web3 come back."
step "Delete web3." \
     "oc delete vm web3 -n $NS --wait=false"
live "watch_traffic 240 'web3'"
say "Rebuilt from the golden image, back in the pool when healthy. The VM, its pool membership and its firewall rules are one definition."

chapter 4 "The app dies, the VM looks fine" \
  "The VM is up, the hypervisor would call it healthy, but the web server inside is dead."
step "Log in to web2 and stop its web server." \
     "virtctl ssh fedora@vmi/web2 -n $NS -i $KEY $SSH_OPTS -c 'sudo systemctl stop webdemo && echo webdemo stopped on \$(hostname)'"
live "watch_traffic 240 'web2'"
say "Readiness took it out of the load balancer, liveness restarted the VM. No ticket, no page."

on && { printf '\n%s' "${C_NOTE}  ── end of demo (any key) ──${C_OFF}"; key; echo; echo; echo "${C_HEAD}  Done · back to the slides  ${C_OFF}"; }
