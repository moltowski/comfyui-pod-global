# comfyui-pod-global

ComfyUI pod image for the RunPod global volume.

ComfyUI and the custom nodes are in the image. Models are on the global volume (`models/`). At start, the pod copies the models it needs to local disk, then starts ComfyUI on port 8188.

## Template

- Image: `ghcr.io/moltowski/comfyui-pod-global:latest`
- Container disk: 100 GB
- Ports: HTTP `8188, 8888`, TCP `22`
- Env: `PRELOAD_MODELS=krea qwen21` (presets: `krea`, `qwen21`, `h3`)

Deploy a pod with this template and attach the global volume in Storage.

Logs: `/models/preload.log` (copy), `/comfyui.log` (ComfyUI).

## Change something

- New model: put it on the volume under `models/<type>/`, add it to `model_presets.txt`.
- New custom node: add `<git url> <commit>` to `nodes.txt`.
- Push to `main`: GitHub Actions rebuilds the image (~30 min).
