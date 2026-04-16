FROM nvcr.io/nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

# ── System deps ───────────────────────────────────────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    python3.11 python3.11-venv python3.11-dev python3-pip \
    git wget curl ffmpeg \
    libgl1-mesa-glx libglib2.0-0 libgomp1 \
    build-essential gcc g++ cmake ninja-build \
    colmap \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# ── Venv 1: radseg — your pipeline Python ─────────────────────────────────────
RUN python -m venv /opt/venv/radseg
RUN /opt/venv/radseg/bin/pip install --upgrade pip setuptools wheel

# PyTorch 2.4 + CUDA 12.1
RUN /opt/venv/radseg/bin/pip install \
    torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 \
    --index-url https://download.pytorch.org/whl/cu121

# RADIO / RADSeg deps
RUN /opt/venv/radseg/bin/pip install \
    timm==1.0.19 \
    einops \
    huggingface-hub \
    transformers \
    open-clip-torch \
    opencv-python-headless \
    Pillow \
    numpy \
    scipy \
    scikit-learn \
    scikit-image \
    matplotlib \
    ftfy \
    regex \
    pyyaml \
    tqdm \
    addict \
    yapf \
    typing_extensions \
    segment-anything \
    gradio

# Pipeline-specific deps
RUN /opt/venv/radseg/bin/pip install \
    plyfile \
    hdbscan \
    joblib \
    omegaconf \
    uv \
    pytest \
    pytest-cov

# faiss — try GPU first, fall back to CPU if linking fails at runtime
RUN /opt/venv/radseg/bin/pip install faiss-gpu-cu12 || \
    /opt/venv/radseg/bin/pip install faiss-cpu

# ── Venv 2: SFS — Splat Feature Solver Python ────────────────────────────────
RUN python -m venv /opt/venv/sfs
RUN /opt/venv/sfs/bin/pip install --upgrade pip setuptools wheel

# PyTorch 2.7 + CUDA 12.8 (as required by SFS)
RUN /opt/venv/sfs/bin/pip install \
    torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
    --index-url https://download.pytorch.org/whl/cu128

RUN /opt/venv/sfs/bin/pip install \
    faiss-gpu-cu12 || /opt/venv/sfs/bin/pip install faiss-cpu

# Clone SFS — CUDA extensions are NOT compiled here.
# Compilation requires a real GPU and is done once at first pod startup via:
#   /opt/venv/sfs/bin/pip install /opt/splat-distiller
RUN git clone --single-branch --branch main \
    https://github.com/saliteta/splat-distiller /opt/splat-distiller

# ── Cache dir for torch hub (RADIO weights) ───────────────────────────────────
# Weights are large (~1.5GB); mount PVC at /workspace so they persist
# across pod restarts and don't re-download every session.
ENV TORCH_HOME=/workspace/.cache/torch
ENV HF_HOME=/workspace/.cache/huggingface

# ── Default working dir and PATH ─────────────────────────────────────────────
WORKDIR /workspace
ENV PATH="/opt/venv/radseg/bin:$PATH"

# Convenience aliases written to bashrc so interactive sessions work cleanly
RUN echo 'alias python-sfs=/opt/venv/sfs/bin/python' >> /etc/bash.bashrc && \
    echo 'alias python-radseg=/opt/venv/radseg/bin/python' >> /etc/bash.bashrc

CMD ["bash"]
