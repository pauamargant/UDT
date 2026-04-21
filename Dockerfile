# We use CUDA 12.1 as it has the best compatibility with current gsplat/faiss builds
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/conda/bin:${PATH}"

# 1. Install System Dependencies (including ffmpeg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    wget \
    cmake \
    build-essential \
    libgl1-mesa-glx \
    libglib2.0-0 \
    ffmpeg \
    colmap \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Miniforge (conda-forge default, no Anaconda TOS prompt in CI)
RUN wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh -O miniforge.sh && \
    bash miniforge.sh -b -p /opt/conda && \
    rm miniforge.sh

WORKDIR /app

# 3. Create environment with a specific Python version to avoid the ABI conflicts you saw
RUN conda create -n splat-distiller python=3.10 -y

# 4. Install PyTorch and Dependencies via Pip (More reliable for CUDA 12.x in Docker)
SHELL ["conda", "run", "-n", "splat-distiller", "/bin/bash", "-c"]

RUN pip install torch==2.1.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121

# 5. Install FAISS-GPU via pip (avoids the Conda solver error you encountered)
RUN pip install faiss-gpu

# 6. Clone and Install the Repo
RUN git clone --single-branch --branch main https://github.com/saliteta/splat-distiller.git .

# CUDA extensions are NOT compiled here — GitHub Actions runners have no GPU.
# Run once at first pod startup: conda run -n splat-distiller pip install -e /app

# 7. Install JupyterLab
RUN pip install jupyterlab

# Clean up
RUN conda clean -afy

EXPOSE 8888

ENTRYPOINT ["/bin/bash"]
