# We use CUDA 12.1 as it has the best compatibility with current gsplat/faiss builds
FROM nvidia/cuda:12.1.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/conda/bin:${PATH}"
ARG USERNAME=appuser
ARG USER_UID=1000
ARG USER_GID=1000

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

# 7. Bootstrap the project and CUDA/native submodules at image build time.
# Mirrors the "first startup" manual steps from docs.
RUN pip install setuptools==68.0.0
RUN cd /app/splat_solver && \
    python -m pip install -e . --no-build-isolation
RUN cd /app/splat_solver/submodules/segment-anything-langsplat && \
    MAX_JOBS=4 python -m pip install . --no-build-isolation
RUN cd /app/splat_solver/submodules/gsplat && \
    MAX_JOBS=4 python -m pip install . --no-build-isolation
RUN cd /app/splat_solver/submodules/bsplat && \
    MAX_JOBS=4 python -m pip install . --no-build-isolation
RUN cd /app/splat_solver/submodules/gsplat_ext && \
    MAX_JOBS=4 python -m pip install . --no-build-isolation

# 8. Create and provision the feature-extraction environment.
RUN conda create -y -n splat-distiller-feat --clone splat-distiller
RUN conda run -n splat-distiller-feat pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121
RUN conda run -n splat-distiller-feat pip install timm==1.0.19 segment-anything scikit-image einops transformers==5.6.0
RUN conda run -n splat-distiller-feat env LD_LIBRARY_PATH=/opt/conda/envs/splat-distiller-feat/lib MAX_JOBS=4 \
    python -m pip install /app/splat_solver/submodules/gsplat --no-build-isolation
RUN conda run -n splat-distiller-feat env LD_LIBRARY_PATH=/opt/conda/envs/splat-distiller-feat/lib MAX_JOBS=4 \
    python -m pip install /app/splat_solver/submodules/bsplat --no-build-isolation
RUN conda run -n splat-distiller-feat env LD_LIBRARY_PATH=/opt/conda/envs/splat-distiller-feat/lib MAX_JOBS=4 \
    python -m pip install /app/splat_solver/submodules/gsplat_ext --no-build-isolation

# 9. Install JupyterLab
RUN pip install jupyterlab

# Clean up
RUN conda clean -afy

# 10. Create non-root runtime user and grant ownership of writable paths.
RUN groupadd --gid ${USER_GID} ${USERNAME} && \
    useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash ${USERNAME} && \
    chown -R ${USERNAME}:${USERNAME} /app /opt/conda

EXPOSE 8888

USER ${USERNAME}

ENTRYPOINT ["/bin/bash"]
