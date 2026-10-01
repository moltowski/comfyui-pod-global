#!/bin/bash
# Appelé par le /start.sh du template RunPod, après SSH et Jupyter.
# 1. trouve le global volume (/workspace-global s'il y a aussi un network volume, sinon /workspace)
# 2. copie en local les modèles de PRELOAD_MODELS
# 3. lance ComfyUI sur 0.0.0.0:8188 (en arrière-plan : start.sh doit pouvoir finir)
# Logs : /models/preload.log, /comfyui.log

(
  if [ -d /workspace-global/models ]; then GV=/workspace-global; else GV=/workspace; fi
  ln -sfn "$GV" /gv
  echo "global volume = $GV ; PRELOAD_MODELS = ${PRELOAD_MODELS:-none}"
  /opt/preload_models.sh "$GV"
  cat /models/preload.log
  cd /opt/ComfyUI
  exec /opt/venv-comfy/bin/python main.py --listen 0.0.0.0 --port 8188 ${COMFY_ARGS:-}
) > /comfyui.log 2>&1 &

echo "ComfyUI : copie des modèles puis démarrage en arrière-plan (tail -f /comfyui.log)"
