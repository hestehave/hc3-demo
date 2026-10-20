#!/usr/bin/env bash
# A day in the life of a VM: a self-typing demo.
#
#   ./dayinlife.sh prep        once, before the session: namespace, VM file, checks
#   ./dayinlife.sh             run the demo from chapter 1
#   ./dayinlife.sh 4           start at chapter 4
#   ./dayinlife.sh reset       delete everything the demo created
#
# During the demo, at each step:
#   any key   type the command and run it
#   s         skip this step          n   skip to the next chapter
#   r         run without typing      q   quit
#
# Settings (environment): TYPE_DELAY=0.03 (seconds per character), PAUSE_BEFORE_RUN=1
# (wait for a key after typing, before running), HC3_KEY=~/.ssh/hc3demo.
# Works with the bash 3.2 that ships with macOS.

set -uo pipefail
cd "$(dirname "$0")"

NS=dayinlife
VM=app1
KEY="${HC3_KEY:-$HOME/.ssh/hc3demo}"
TYPE_DELAY="${TYPE_DELAY:-0.03}"
PAUSE_BEFORE_RUN="${PAUSE_BEFORE_RUN:-0}"

# ---------- colours ----------
if [ -t 1 ]; then
  C_DESC=$'\033[1;36m'; C_NOTE=$'\033[2;37m'; C_CMD=$'\033[1;37m'; C_PROMPT=$'\033[1;32m'
  C_HEAD=$'\033[1;41;37m'; C_WARN=$'\033[1;33m'; C_OFF=$'\033[0m'
else
  C_DESC=; C_NOTE=; C_CMD=; C_PROMPT=; C_HEAD=; C_WARN=; C_OFF=
fi

# ---------- helpers used by the typed commands ----------
# vssh: virtctl ssh into the VM as fedora, without host-key prompts (the VM is new every time)
vssh() {
  virtctl ssh "fedora@vm/$1" -n "$NS" -i "$KEY" \
    --local-ssh-opts="-o StrictHostKeyChecking=no" \
    --local-ssh-opts="-o UserKnownHostsFile=/dev/null" \
    --local-ssh-opts="-o LogLevel=ERROR" \
    -c "$2"
}

# ---------- helpers used behind the scenes ----------
mig_count() { oc get vmim -n "$NS" -o name 2>/dev/null | wc -l | tr -d ' '; }

# Wait for a live migration newer than count $1 to finish, printing its phases.
wait_migration() {
  local before="$1" waited=0 last="" phase
  printf '%s' "${C_NOTE}  (watching the live migration)${C_OFF}"; echo
  while [ "$waited" -lt 240 ]; do
    if [ "$(mig_count)" -gt "$before" ]; then
      phase="$(oc get vmim -n "$NS" --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1:].status.phase}' 2>/dev/null)"
      if [ -n "$phase" ] && [ "$phase" != "$last" ]; then
        echo "  $(date +%T)  migration: $phase"; last="$phase"
      fi
      case "$phase" in Succeeded|Failed) return 0 ;; esac
    elif [ "$waited" -ge 60 ]; then
      echo "${C_WARN}  No migration started after 60 s. Check: oc get vm $VM -n $NS -o jsonpath='{.status.conditions}'${C_OFF}"
      return 1
    fi
    sleep 2; waited=$((waited + 2))
  done
  echo "${C_WARN}  Migration still running after 4 minutes; carry on and check the console.${C_OFF}"
}

# ---------- the presentation engine ----------
START="${1:-1}"
CUR=0
SKIP_CHAPTER=0

key() {  # read one key, act on q
  local k
  IFS= read -rsn1 k </dev/tty
  [ "$k" = "q" ] && { echo; echo "bye"; exit 0; }
  KEY_PRESSED="$k"
}

active() { [ "$CUR" -ge "$START" ] && [ "$SKIP_CHAPTER" -eq 0 ]; }

chapter() {  # chapter <number> <title> <one line on the vSphere equivalent>
  CUR="$1"; SKIP_CHAPTER=0
  active || return 0
  clear
  echo
  printf '%s\n' "${C_HEAD}  $1 · $2  ${C_OFF}"
  [ -n "${3:-}" ] && printf '%s\n' "${C_NOTE}  $3${C_OFF}"
  echo
}

# step <description> <command> [note]
step() {
  active || return 0
  local desc="$1" cmd="$2" note="${3:-}" i
  STEP_RAN=0
  echo
  printf '%s\n' "${C_DESC}# $desc${C_OFF}"
  [ -n "$note" ] && printf '%s\n' "${C_NOTE}#   $note${C_OFF}"
  key
  case "$KEY_PRESSED" in
    s) echo "${C_NOTE}  (skipped)${C_OFF}"; return 0 ;;
    n) echo "${C_NOTE}  (skipping to the next chapter)${C_OFF}"; SKIP_CHAPTER=1; return 0 ;;
  esac
  printf '%s' "${C_PROMPT}\$ ${C_OFF}${C_CMD}"
  if [ "$KEY_PRESSED" = "r" ]; then
    printf '%s' "$cmd"
  else
    for ((i = 0; i < ${#cmd}; i++)); do
      printf '%s' "${cmd:i:1}"
      sleep "$TYPE_DELAY"
    done
  fi
  printf '%s\n' "$C_OFF"
  [ "$PAUSE_BEFORE_RUN" = "1" ] && key
  STEP_RAN=1
  eval "$cmd"
}

# say <text>: a line for you to talk over, no command
say() {
  active || return 0
  echo
  printf '%s\n' "${C_DESC}# $1${C_OFF}"
  key
  case "$KEY_PRESSED" in n) SKIP_CHAPTER=1 ;; esac
}

# hidden <command>: runs without being typed (waits, bookkeeping)
hidden() { active || return 0; eval "$1"; }
# after_step <command>: hidden, and only if the step before it actually ran
after_step() { active || return 0; [ "${STEP_RAN:-0}" = 1 ] || return 0; eval "$1"; }

# ---------- prep and reset ----------
if [ "${1:-}" = "prep" ]; then
  ok=1
  for t in oc virtctl; do command -v "$t" >/dev/null || { echo "missing: $t"; ok=0; }; done
  [ -f "$KEY.pub" ] || { echo "missing SSH key $KEY.pub (ssh-keygen -t ed25519 -N \"\" -f $KEY)"; ok=0; }
  oc whoami >/dev/null 2>&1 || { echo "not logged in: oc login ..."; ok=0; }
  [ "$ok" = 1 ] || exit 1

  export R_KEY="$(cat "$KEY.pub")"
  awk 'BEGIN { key = ENVIRON["R_KEY"] }
       /^#/ { next }
       { line = $0
         while ((i = index(line, "__SSH_PUBKEY__")) > 0) line = substr(line, 1, i-1) key substr(line, i+14)
         print line }' life/app1.yaml.tpl > life/app1.yaml
  echo "wrote life/app1.yaml"

  oc get project "$NS" >/dev/null 2>&1 || oc new-project "$NS" >/dev/null
  echo "namespace $NS ready"

  strategy="$(oc get kubevirt -n openshift-cnv -o jsonpath='{.items[0].spec.configuration.vmRolloutStrategy}' 2>/dev/null)"
  echo "VM rollout strategy: ${strategy:-unknown} (chapter 3 needs LiveUpdate for hot-add)"
  oc get datasource fedora -n openshift-virtualization-os-images >/dev/null 2>&1 \
    && echo "Fedora golden image: present" || echo "Fedora golden image: MISSING"
  oc get volumesnapshotclass -o name | grep -q . \
    && echo "snapshot class: present" || echo "snapshot class: MISSING (chapter 5 will fail)"
  oc get vm "$VM" -n "$NS" >/dev/null 2>&1 && echo "${C_WARN}app1 already exists: run ./dayinlife.sh reset first${C_OFF}"
  exit 0
fi

if [ "${1:-}" = "reset" ]; then
  oc delete vmrestore --all -n "$NS" --ignore-not-found
  oc delete vmsnapshot --all -n "$NS" --ignore-not-found
  oc delete vm "$VM" -n "$NS" --ignore-not-found --wait=true
  oc delete vmim --all -n "$NS" --ignore-not-found
  echo "reset done; the namespace stays. Delete it after the event with: oc delete project $NS"
  exit 0
fi

case "$START" in [1-7]) ;; *) echo "usage: ./dayinlife.sh [prep | reset | <chapter 1-7>]"; exit 1 ;; esac
[ -f life/app1.yaml ] || { echo "run ./dayinlife.sh prep first"; exit 1; }

# =====================================================================
#  The story
# =====================================================================

chapter 1 "Monday 09:00 · The request" "vSphere: New VM from template, or a ticket to the VMware team"

step "A team asks for a VM. This is the whole request: size, OS, a disk from the golden image." \
     "grep -v -e cloud-config -e '^            ' life/app1.yaml" \
     "The cloud-init details (user, SSH key) are left out of the view to keep it short"

step "Submit it. The same file works from Git, a pipeline, or a self-service form." \
     "oc apply -f life/app1.yaml"

step "The disk is cloned from the golden image on the storage array, then the VM boots." \
     "oc get vm,dv,pvc -n $NS" \
     "With Ceph or an enterprise array this clone is copy-on-write: seconds, not a full copy"

step "Wait for it to report Ready (about a minute)." \
     "oc wait vm/$VM -n $NS --for=condition=Ready --timeout=5m"

chapter 2 "Monday 09:05 · Where is it, and what did it get?" "vSphere: the VM's Summary tab, datastore browser and port group"

step "Which host is it running on, and what is its IP?" \
     "oc get vmi $VM -n $NS -o wide"

step "Every VM runs inside a small envelope pod: that is how Kubernetes schedules and secures it." \
     "oc get pods -n $NS -l vm.kubevirt.io/name=$VM -o wide" \
     "Inside it is plain QEMU/KVM. The pod is the unit the scheduler, network and security policies understand"

step "Its disk: a persistent volume from a storage class, the equivalent of a VMDK on a datastore." \
     "oc get pvc -n $NS -o custom-columns='DISK:.metadata.name,SIZE:.status.capacity.storage,CLASS:.spec.storageClassName,ACCESS:.spec.accessModes[0],MODE:.spec.volumeMode'" \
     "RWX block means two hosts can open it at once: that is what makes live migration possible"

step "Its network: interface, IP and MAC, as the guest agent reports them." \
     "oc get vmi $VM -n $NS -o jsonpath='{range .status.interfaces[*]}{.name}{\"  \"}{.ipAddress}{\"  \"}{.mac}{\"\\n\"}{end}'"

step "Log in. vssh is a two-line wrapper around 'virtctl ssh' that skips the host-key prompt." \
     "vssh $VM 'hostname; nproc; free -h | head -2; uptime -p'" \
     "No IP or jump host needed: the connection goes through the API, with the same RBAC as everything else"

chapter 3 "Wednesday 14:00 · It needs more" "vSphere: CPU and memory hot-add"

hidden 'MIG_BEFORE=$(mig_count)'
step "The team asks for 2 vCPUs and 4 GiB. Change the VM's definition while it runs." \
     "oc patch vm $VM -n $NS --type merge -p '{\"spec\":{\"template\":{\"spec\":{\"domain\":{\"cpu\":{\"sockets\":2},\"memory\":{\"guest\":\"4Gi\"}}}}}}'" \
     "On OpenShift the hot-add is done by live-migrating the VM to a new envelope with the new size"
after_step 'wait_migration $MIG_BEFORE'

step "Same VM, still running, now bigger." \
     "vssh $VM 'nproc; free -h | head -2; uptime -p'" \
     "Memory can grow to 4x the boot size without a restart; the guest needs virtio-mem (any recent Linux, current Windows drivers)"

chapter 4 "Thursday 22:00 · The host needs patching" "vSphere: vMotion, or maintenance mode with DRS"

step "Note which host it is on now." \
     "oc get vmi $VM -n $NS -o custom-columns='VM:.metadata.name,NODE:.status.nodeName,IP:.status.interfaces[0].ipAddress'"

hidden 'MIG_BEFORE=$(mig_count)'
step "Live-migrate it. Maintenance mode does exactly this for every VM on a node." \
     "virtctl migrate $VM -n $NS" \
     "A cluster upgrade drains each node like this, one at a time, automatically"
after_step 'wait_migration $MIG_BEFORE'

step "New host, same IP, and the uptime shows it never rebooted." \
     "oc get vmi $VM -n $NS -o custom-columns='VM:.metadata.name,NODE:.status.nodeName,IP:.status.interfaces[0].ipAddress' && vssh $VM 'uptime -p'"

chapter 5 "Friday 10:00 · Patch day" "vSphere: take a snapshot before the change"

step "Snapshot before the change. This is a storage-array snapshot through CSI, not a delta disk." \
     "oc apply -f life/snapshot.yaml && oc wait vmsnapshot app1-before-patch -n $NS --for=jsonpath='{.status.readyToUse}'=true --timeout=3m"

step "The patch goes wrong: someone breaks the application's config." \
     "vssh $VM 'echo \"max_connections = 0   # oops\" | sudo tee /etc/app.conf'"

step "Roll back, step 1: shut the VM down." \
     "virtctl stop $VM -n $NS && oc wait vm/$VM -n $NS --for=jsonpath='{.status.printableStatus}'=Stopped --timeout=3m" \
     "Talk while it stops: no snapshot chains to consolidate, and backup tools use these same snapshots"

step "Step 2: restore the snapshot (disk and VM definition)." \
     "oc apply -f life/restore.yaml && oc wait vmrestore app1-restore -n $NS --for=jsonpath='{.status.complete}'=true --timeout=3m"

step "Step 3: start it again." \
     "virtctl start $VM -n $NS 2>/dev/null; oc wait vm/$VM -n $NS --for=condition=Ready --timeout=5m"

step "The bad change is gone." \
     "sleep 20; vssh $VM 'cat /etc/app.conf 2>&1 || true; uptime -p'" \
     "The 20 s pause gives sshd time to start after the boot"

chapter 6 "Next quarter · Who owns it, and what does it cost?" "vSphere: tags, folders and vROps"

step "Everything about it is in one object you can query: owner label, size, state." \
     "oc get vm -n $NS -L owner -o wide"

step "Live resource use, from the same monitoring stack as every other workload." \
     "oc adm top pod -n $NS"

chapter 7 "End of life · Decommission" "vSphere: delete from disk, then clean up DNS, firewall rules and the CMDB"

step "Delete the VM. Its disk goes with it, because it was declared as part of the VM." \
     "oc delete vm $VM -n $NS && oc get vm,pvc -n $NS"

say "That's a day in the life: requested, placed, resized, moved, rolled back and retired, all through one API. (Press a key to finish.)"
echo
