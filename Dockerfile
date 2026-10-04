# comfyui-pod-global : image de POD ComfyUI pour le global volume RunPod.
#
# Principe (mesuré le 29/09, cf. research/global-volume-2026-09-29) :
#   - le global volume est du stockage objet : pas de chmod +x, pas de .so chargeable, pas de git
#     -> ComfyUI, son venv et les custom nodes sont DANS l'image ;
#   - ComfyUI qui lit les modèles directement sur le volume = 12 min au 1er rendu Qwen 2.1
#     -> au démarrage, pre_start.sh copie en local les modèles listés dans PRELOAD_MODELS
#        (~146 Mo/s), puis lance ComfyUI sur ces copies locales.
#
# Base = template officiel RunPod PyTorch 2.8 (CUDA 12.8, OK Blackwell), celui du test du 29/09 :
# il garde SSH et son /start.sh exécute /pre_start.sh (pas /post_start.sh : vérifié le 04/10 sur un pod).

ARG BASE=runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404
FROM ${BASE}

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1

# ffmpeg : VideoHelperSuite / SaveVideo ; libgl1 + libglib : opencv (WAS, KJNodes).
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg libgl1 libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

# 1. ComfyUI épinglé au commit testé le 29/09 (v0.37.0, nodes natifs Qwen 2.1).
ARG COMFYUI_SHA=a7169322485d0049380fb207fa17e9fb3ec40486
RUN git clone -q https://github.com/comfyanonymous/ComfyUI.git /opt/ComfyUI && \
    git -C /opt/ComfyUI checkout -q ${COMFYUI_SHA}

# 2. venv qui réutilise le torch 2.8 du template (--system-site-packages) ; les contraintes
#    empêchent un requirements.txt de node de remplacer torch.
RUN python3 -m venv --system-site-packages /opt/venv-comfy && \
    /opt/venv-comfy/bin/python -m pip freeze | grep -iE '^(torch|torchvision|torchaudio)==' > /opt/torch-constraints.txt && \
    cat /opt/torch-constraints.txt && \
    /opt/venv-comfy/bin/pip install -q -c /opt/torch-constraints.txt -r /opt/ComfyUI/requirements.txt

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
RUN /opt/venv-comfy/bin/python -c "import torch; print('torch', torch.__version__)" && \
    cd /opt/ComfyUI && \
    timeout 600 /opt/venv-comfy/bin/python main.py --cpu --quick-test-for-ci > /tmp/import-test.log 2>&1; \
    cat /tmp/import-test.log | tail -40; \
    ! grep -q "IMPORT FAILED" /tmp/import-test.log

EXPOSE 8188
