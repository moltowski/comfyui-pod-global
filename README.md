# comfyui-pod-global

Pod image for ComfyUI on a RunPod **global volume**.

- ComfyUI, its Python env and the custom nodes are inside the image (the global volume can't run code: no `chmod +x`, no `.so` loading, no git).
- Models live on the global volume under `models/`. At start, the pod copies the models it needs to its local disk, then starts ComfyUI on them. Reading the models straight from the volume took 12 min for the first Qwen-Image 2.1 render; copying first takes ~4 min in total (test of 2026-09-29).

Image: `ghcr.io/moltowski/comfyui-pod-global:latest` (built by GitHub Actions on every push to `main`).

## RunPod template

| Setting | Value |
|---|---|
| Container image | `ghcr.io/moltowski/comfyui-pod-global:latest` |
| Container disk | enough for the copied models + ~30 GB (Krea ~35 GB, Qwen 2.1 ~35 GB, H3 ~75 GB) |
| Volume | the global volume (mounted on `/workspace`, or `/workspace-global` if a network volume is attached too) |
| HTTP ports | `8188` (ComfyUI), `8888` (Jupyter) |
| TCP ports | `22` (SSH) |
| Env `PRELOAD_MODELS` | presets and/or paths, space separated, e.g. `krea`, `qwen21`, `h3`, `krea qwen21` |
| Env `COMFY_ARGS` | optional extra ComfyUI arguments |

Presets are in `model_presets.txt`. A path can be given directly too (relative to `models/`, e.g. `vae/wan_2.1_vae.safetensors`). `loras/` is always copied.

## What happens at start

1. RunPod's `/start.sh` starts SSH and Jupyter, then runs `/post_start.sh`.
2. `post_start.sh` copies the models (4 at a time) to `/models` → log in `/models/preload.log`.
3. ComfyUI starts on port 8188 → log in `/comfyui.log`.

A model that was not copied is still found on the global volume (second path in `extra_model_paths.yaml`), but it loads slowly.

## Add a model

Put the file on the global volume under `models/<type>/`, then add it to a preset in `model_presets.txt` (or list it in `PRELOAD_MODELS`). No rebuild needed for `PRELOAD_MODELS`; a preset change needs a rebuild.

## Add a custom node

Add a line `<git url> <commit sha>` to `nodes.txt`, push, wait for the build.
