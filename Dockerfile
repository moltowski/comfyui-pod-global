# comfyui-pod-global : image de POD ComfyUI pour le global volume RunPod.
#
# Principe (mesuré le 29/09, cf. research/global-volume-2026-09-29) :
#   - le global volume est du stockage objet : pas de chmod +x, pas de .so chargeable, pas de git
#     -> ComfyUI, son venv et les custom nodes sont DANS l'image ;
#   - ComfyUI qui lit les modèles directement sur le volume = 12 min au 1er rendu Qwen 2.1
#     -> au démarrage, pre_start.sh copie en local les modèles listés dans PRELOAD_MODELS
#        (~146 Mo/s), puis lance ComfyUI sur ces copies locales.
#
# Base = template officiel RunPod PyTorch (celui du test du 29/09) : il garde SSH et son /start.sh
# exécute /pre_start.sh (pas /post_start.sh : vérifié le 04/10 sur un pod). Son torch 2.8 n'est PAS
# utilisé : le venv a son propre torch 2.12 + cu130, comme les workers serverless (H3 2x plus rapide
# qu'en cu128, trouvé le 09/11). Il faut donc un hôte avec un driver CUDA >= 13.0.

ARG BASE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${BASE}

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# ffmpeg : VideoHelperSuite / SaveVideo ; libgl1 + libglib : opencv (WAS, KJNodes).
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# 1. ComfyUI v0.45.0 (2026-11-10), même SHA que les workers serverless : une seule version partout.
#    Natif : MiniMax H3-Image (MiniMaxH3ImageConditioning) et limite RAM du cgroup respectée (>= 0.35).
ARG COMFYUI_SHA=989d93d0d968e704c589ce0146bb18c77f6b50cc
RUN git clone -q https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    git -C /opt/ComfyUI checkout -q ${COMFYUI_SHA} && \
    grep -q "MiniMaxH3ImageConditioning" /opt/ComfyUI/comfy_extras/nodes_minimax_h3.py

# 2. venv avec son propre torch = celui des workers serverless (2.12.0 + cu130, torchvision 0.27.0,
#    torchaudio 2.11.0 importé par le node natif H3) ; les contraintes empêchent un requirements.txt
#    de node de le remplacer.
ARG TORCH=2.12.0 TORCHVISION=0.27.0 TORCHAUDIO=2.11.0 TORCH_INDEX=https://download.pytorch.org/whl/cu130
RUN python3 -m venv /opt/venv-comfy && \
    /opt/venv-comfy/bin/pip install -q --upgrade pip && \
    /opt/venv-comfy/bin/pip install -q "torch==${TORCH}" "torchvision==${TORCHVISION}" "torchaudio==${TORCHAUDIO}" --index-url ${TORCH_INDEX} && \
    /opt/venv-comfy/bin/python -m pip freeze | grep -iE '^(torch|torchvision|torchaudio)==' > /opt/torch-constraints.txt && \
    cat /opt/torch-constraints.txt && \
    /opt/venv-comfy/bin/pip install -q -c /opt/torch-constraints.txt -r /opt/ComfyUI/requirements.txt && \
    /opt/venv-comfy/bin/python -c "import sys; sys.path.insert(0,'/opt/ComfyUI'); from comfyui_version import __version__ as v; print('ComfyUI', v); assert v.startswith('0.45'), v"

# 3. Custom nodes publics, épinglés au SHA (liste dans nodes.txt) + leurs dépendances.
COPY nodes.txt /opt/nodes.txt
RUN cd /opt/ComfyUI/custom_nodes && \
    grep -vE '^\s*(#|$)' /opt/nodes.txt | while read url sha; do \
      d=$(basename "$url" .git); \
      git clone -q "$url" "$d" && git -C "$d" checkout -q "$sha" || exit 1; \
      if [ -f "$d/requirements.txt" ]; then \
        /opt/venv-comfy/bin/pip install -q -c /opt/torch-constraints.txt -r "$d/requirements.txt" || exit 1; \
      fi; \
      echo "node $d @ $sha"; \
    done

# 4. Nos nodes (PT_InputHub v2, PT_LoadAudioOptional).
COPY custom_nodes/ /opt/ComfyUI/custom_nodes/

# 5. Chemins des modèles + scripts de démarrage.
COPY extra_model_paths.yaml /opt/ComfyUI/extra_model_paths.yaml
COPY model_presets.txt /opt/model_presets.txt
COPY preload_models.sh /opt/preload_models.sh
COPY pre_start.sh /pre_start.sh
RUN chmod +x /opt/preload_models.sh /pre_start.sh

# 6. Vérification au build : torch n'a pas bougé, et ComfyUI + tous les nodes s'importent.
RUN /opt/venv-comfy/bin/python -c "import torch, torchaudio; print('torch', torch.__version__, 'cuda', torch.version.cuda); assert torch.version.cuda.startswith('13')" && \
    cd /opt/ComfyUI && \
    timeout 600 /opt/venv-comfy/bin/python main.py --cpu --quick-test-for-ci > /tmp/import-test.log 2>&1; \
    cat /tmp/import-test.log | tail -40; \
    ! grep -q "IMPORT FAILED" /tmp/import-test.log

EXPOSE 8188
