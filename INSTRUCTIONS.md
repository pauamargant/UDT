# UDT — Setup & Usage Instructions

## Docker Image

The image is built automatically via GitHub Actions on every push to `master` and pushed to:

```
ghcr.io/pauamargant/udt:master
```

Check build status: https://github.com/pauamargant/UDT/actions

---

## RunAI (RCP EPFL)

### Submit interactive job

```bash
/c/CLI/runai.exe submit semantic-twin-dev \
  --image ghcr.io/pauamargant/udt:master \
  --gpu 1 --cpu 8 --memory 32G \
  --interactive \
  --pvc dhlab-scratch:/workspace \
  -p dhlab-amargant \
  -- -c "sleep infinity"
```

### Connect

```bash
/c/CLI/runai.exe exec semantic-twin-dev -p dhlab-amargant -it -- bash
```

### First startup — compile splat-distiller CUDA extensions (one-time, ~15 min)

The image ships the source at `/app` but skips CUDA compilation (no GPU on CI runners).
Run this once inside the pod:

```bash
conda activate splat-distiller
pip install setuptools==68.0.0          # torch 2.1 needs older setuptools
pip install --no-build-isolation -e /app
```

### Subsequent startups

CUDA extensions are compiled into the conda env inside the container. They are lost when the pod is deleted. Re-run the compilation step above on each new pod.

> **Tip:** If you want to persist the compiled env across pod restarts, install into `/workspace` (the PVC) instead.

---

## JupyterLab

Start inside the pod:

```bash
conda activate splat-distiller
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token=''
```

Port-forward from your local machine (separate terminal):

```bash
kubectl port-forward -n runai-dhlab-amargant pod/semantic-twin-dev-0-0 8888:8888
```

Then open: http://localhost:8888

---

## Remote development (Antigravity / VS Code)

The image runs `sshd` automatically on startup. Set a password inside the pod first:

```bash
echo 'root:YOUR_PASSWORD' | chpasswd
```

Port-forward SSH from your local machine:

```bash
kubectl port-forward -n runai-dhlab-amargant pod/semantic-twin-dev-0-0 2222:22
```

Then connect via Remote SSH to `root@localhost:2222`, or add to `~/.ssh/config`:

```
Host runai-pod
    HostName localhost
    Port 2222
    User root
```

---

## Cluster resources

| Resource | Name |
|---|---|
| Project | `dhlab-amargant` |
| PVC (scratch) | `dhlab-scratch` → mounted at `/workspace` |
| PVC (home) | `home` |

## Job management

```bash
# List jobs
/c/CLI/runai.exe list jobs -p dhlab-amargant

# Logs
/c/CLI/runai.exe logs semantic-twin-dev -p dhlab-amargant

# Delete (always do this when done — costs GPU quota)
/c/CLI/runai.exe delete job semantic-twin-dev -p dhlab-amargant
```
