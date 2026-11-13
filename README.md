# comfyui-pod-global

Pod image for ComfyUI on a RunPod **global volume**.

- ComfyUI 0.45.0 with torch 2.12 + CUDA 13.0 (same as the serverless workers), its Python env and the custom nodes are inside the image (the global volume can't run code: no `chmod +x`, no `.so` loading, no git).
- Models live on the global volume under `models/`. At start, the pod copies the models it needs to its local disk, then starts ComfyUI on them. Reading the models straight from the volume took 12 min for the first Qwen-Image 2.1 render; copying first takes ~4 min in total (test of 2026-09-29).

Image: `ghcr.io/moltowski/comfyui-pod-global:<commit sha>` (built by GitHub Actions on every push; `main` also gets `:latest`, other branches `:<branch>`). Use the commit tag in templates: a host may keep an old `:latest` in cache.

The host driver must support **CUDA 13.0** (filter on CUDA 13.0 when deploying).

## RunPod template

| Setting | Value |
|---|---|
| Container image | `ghcr.io/moltowski/comfyui-pod-global:<commit sha>` |
| Container disk | copied models + ~30 GB: `krea` 60 GB, `h3image` 100 GB, `h3` 110 GB |
| Volume | the global volume (mounted on `/workspace`, or `/workspace-global` if a network volume is attached too) |
| HTTP ports | `8188` (ComfyUI), `8888` (Jupyter) |
| TCP ports | `22` (SSH) |
| Env `PRELOAD_MODELS` | presets and/or paths, separated by spaces or commas: `krea`, `h3image` or `h3`. One family per pod. |
| Env `PRELOAD_LORAS` | `all` (default, the whole `loras/` folder), `none`, or a list of paths under `loras/`, e.g. `character/nv_e4u66d_k2,lenovo` |
| Env `COMFY_ARGS` | optional extra ComfyUI arguments |

Presets are in `model_presets.txt`. A path can be given directly too (relative to `models/`, e.g. `vae/wan_2.1_vae.safetensors`).

| Preset | Files | Size | GPU |
|---|---|---|---|
| `krea` | FinePorn v5 BF16 (prod), Qwen3-VL 4B fp8, Qwen Image VAE | ~31 GB | any card with ≥ 32 GB |
| `h3image` | MiniMax H3-Image DiT bf16, Qwen3-VL 32B int8, H3-Image VAE | ~68 GB | RTX PRO 6000 (peak 68 GB VRAM, ~70 GB RAM) |
| `h3` | MiniMax H3 video ref2va + fl2va, Qwen3-VL 32B int8, video + audio VAE | ~76 GB | RTX PRO 6000 |

Character LoRAs: `PRELOAD_LORAS=all` is fine for a few dozen characters (~230 MB each). At hundreds, list only the fixed LoRAs at boot and copy each character LoRA when its job arrives (not built yet).

## What happens at start

1. RunPod's `/start.sh` runs `/pre_start.sh` (it does not run `/post_start.sh` in this base image), then starts SSH.
2. `pre_start.sh` copies the models one at a time (3 tries each) to `/models` → log in `/models/preload.log`, with the speed of each file.
3. ComfyUI starts on port 8188 once the copy is done (~4 min for `krea` at 150 MB/s) → log in `/comfyui.log`.

Outputs go to `/opt/ComfyUI/output` on the container disk and are lost when the pod stops.

A model that was not copied is still found on the global volume (second path in `extra_model_paths.yaml`), but it loads slowly.

## Add a model

Put the file on the global volume under `models/<type>/`, then add it to a preset in `model_presets.txt` (or list it in `PRELOAD_MODELS`). No rebuild needed for `PRELOAD_MODELS`; a preset change needs a rebuild.

## Add a custom node

Add a line `<git url> <commit sha>` to `nodes.txt`, push, wait for the build.
