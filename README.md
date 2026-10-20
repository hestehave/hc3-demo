# HC3 demo: "Break it on purpose"

A three-tier shop (web1–3, db) on OpenShift Virtualization 4.22, owned by Argo CD.
The full script, with timing and talk track, is in the lab doc's "HC3 demo script" tab.

## Layout

| Path | What | Synced by Argo CD |
| --- | --- | --- |
| `manifests/` | VMs, Services, Route, NetworkPolicies | Yes |
| `extras/web-container.yaml` | The container you add live in step 4 | Only after you copy it into `manifests/` |
| `ops/` | Argo Application, rogue pod, image pre-pull | No (applied by hand) |
| `templates/` + `render.sh` | Generates the VM manifests with your SSH key | No |
| `demo.sh` | The commands you run during the demo | No |

## Setup in short

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/hc3demo
./render.sh ~/.ssh/hc3demo.pub
git init -b main && git add . && git commit -m "HC3 shop"
github .     # GitHub Desktop: Publish repository, untick "Keep this code private"
```

`ops/argo-app.yaml` already points at https://github.com/hestehave/hc3-demo.git.

The repo must be public (or add it as a repository in Argo CD with credentials).
The VMs need no internet access: the web and "database" listeners are Python's built-in HTTP server.

## A day in the life of a VM (`dayinlife.sh`)

A self-typing demo: each step shows a one-line description, and a key press types the
command and runs it. It uses its own namespace, `dayinlife`, which Argo CD does not manage.

```bash
./dayinlife.sh prep     # once: renders life/app1.yaml with your SSH key, creates the namespace, checks
./dayinlife.sh          # run from chapter 1   (./dayinlife.sh 4 starts at chapter 4)
./dayinlife.sh reset    # delete the VM, snapshot and restore so you can run it again
```

Keys: any key = type and run · `r` = run without typing · `s` = skip step · `n` = next chapter · `q` = quit.
Slower or faster typing: `TYPE_DELAY=0.05 ./dayinlife.sh`. Pause after typing, before running: `PAUSE_BEFORE_RUN=1`.

| Chapter | Story | vSphere equivalent | About |
| --- | --- | --- | --- |
| 1 | The request: VM from the golden image | New VM from template | 2 min (boot) |
| 2 | Where is it: node, envelope pod, disk, IP, SSH | Summary tab | 1.5 min |
| 3 | It needs more: 2 vCPU / 4 GiB while running | Hot-add | 1.5 min |
| 4 | The host needs patching: live migration | vMotion / maintenance mode | 1.5 min |
| 5 | Patch day: snapshot, break, restore | Snapshot and revert | 3–4 min |
| 6 | Owner and usage | Tags, vROps | 0.5 min |
| 7 | Decommission | Delete from disk | 0.5 min |
