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
