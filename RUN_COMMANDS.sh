# Docker build, push, and pod launch
# Platform: Windows — run all LOCAL commands in PowerShell
# Commands marked INSIDE POD run in bash after `runai exec`
# PVC: dhlab-scratch-amargant (100Ti, RWX)
# Registry: registry.rcp.epfl.ch/idhlab-amargant/

# ══════════════════════════════════════════════════════════════════════════════
# LOCAL MACHINE (PowerShell)
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. Build ──────────────────────────────────────────────────────────────────
# Run from the project root (where docker/Dockerfile lives)
# --platform linux/amd64 required on Windows — Docker Desktop uses a Linux VM
# but we force amd64 so the image runs on the cluster's x86 GPUs
# Expect ~20-30 min — SFS CUDA extension compile is the slow step

docker build --platform linux/amd64 -t registry.rcp.epfl.ch/idhlab-amargant/semantic-twin:v1 -f docker/Dockerfile .

# ── 2. Push ───────────────────────────────────────────────────────────────────
docker login registry.rcp.epfl.ch
docker push registry.rcp.epfl.ch/idhlab-amargant/semantic-twin:v1

# ── 3. Launch interactive pod ─────────────────────────────────────────────────
runai submit semantic-twin-dev --image registry.rcp.epfl.ch/idhlab-amargant/semantic-twin:v1 --gpu 1 --cpu 8 --memory 32G --interactive --pvc dhlab-scratch-amargant:/workspace -- sleep infinity

# Wait ~30 seconds for pod to start, then:
runai list jobs

# ── 4. Connect ────────────────────────────────────────────────────────────────
runai exec semantic-twin-dev -it -- bash
# You are now inside the container. Prompt changes to root@<pod-name>:/workspace#

# ── 7. Copy files to/from pod (PowerShell) ───────────────────────────────────
# Get the pod name first:
kubectl get pods

# Upload your video (replace <pod-name> with actual name from above):
kubectl cp your_video.mp4 <pod-name>:/workspace/data/room_01/your_video.mp4

# Download radio_check.png after running the sanity check:
kubectl cp <pod-name>:/workspace/scripts/radio_check.png radio_check.png

# ── 6. Pod management (PowerShell) ───────────────────────────────────────────
runai list jobs
runai logs semantic-twin-dev
runai describe job semantic-twin-dev
runai delete job semantic-twin-dev     # ALWAYS do this when done — costs money


# ══════════════════════════════════════════════════════════════════════════════
# INSIDE POD (bash — after runai exec)
# ══════════════════════════════════════════════════════════════════════════════

# ── 5a. Smoke test radseg venv ────────────────────────────────────────────────
/opt/venv/radseg/bin/python -c "import torch; print('radseg:', torch.__version__, torch.cuda.is_available())"
# expect: radseg: 2.4.x True

# ── 5b. Compile SFS CUDA extensions (first pod startup only, ~10 min) ────────
# The image ships the source at /opt/splat-distiller but skips compilation
# because GitHub Actions runners have no GPU. Run this once; the compiled
# .so files land inside the venv and persist for the lifetime of the pod.
/opt/venv/sfs/bin/pip install /opt/splat-distiller

# Smoke test SFS venv
/opt/venv/sfs/bin/python -c "import torch; print('sfs:', torch.__version__, torch.cuda.is_available())"
# expect: sfs: 2.7.x True

# ── 5c. Smoke test faiss ──────────────────────────────────────────────────────
/opt/venv/radseg/bin/python -c "import faiss; print('faiss:', faiss.__version__)"

# ── 5d. Smoke test COLMAP ─────────────────────────────────────────────────────
colmap --version

# ── 5e. RADIO hub load ────────────────────────────────────────────────────────
# Downloads ~1.5GB to /workspace/.cache/torch — only on first run
/opt/venv/radseg/bin/python -c "
import torch
m = torch.hub.load('NVlabs/RADIO', 'radio_model', version='c-radio_v3-l', adaptor_names=['clip', 'dino_v2'], progress=True, skip_validation=True)
print('RADIO OK | patch_size:', m.patch_size)
"

# ── Notes ─────────────────────────────────────────────────────────────────────
# /workspace          — your PVC, persists across pod restarts
# /workspace/.cache   — RADIO + HF weights cached here, survives pod deletion
# /opt/venv/radseg    — your pipeline Python (active by default)
# /opt/venv/sfs       — SFS Python (call explicitly as /opt/venv/sfs/bin/python)
# /opt/splat-distiller — SFS repo, baked into image
# Rebuild image: bump tag to v2, v3 etc and re-push
