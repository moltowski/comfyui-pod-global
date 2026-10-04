#!/bin/bash
# Copie du global volume vers le disque local (/models) les modèles demandés.
#   PRELOAD_MODELS="krea qwen21"                   -> presets de /opt/model_presets.txt
#   PRELOAD_MODELS="krea vae/autre.safetensors"     -> on peut mélanger presets et chemins
#   PRELOAD_MODELS="none" (ou vide)                 -> ne copie que loras/
#   Séparateur : espace ou virgule ("qwen21,krea" marche aussi).
# 4 copies en parallèle. Log : /models/preload.log ; fin : /models/.preload_done
set -u
SRC="$1/models"
DST=/models
mkdir -p "$DST"
LOG="$DST/preload.log"
: > "$LOG"

items=("loras/")
LIST="${PRELOAD_MODELS:-none}"
for w in ${LIST//,/ }; do
  [ "$w" = none ] && continue
  hits=$(awk -v p="$w" '$1==p {print $2}' /opt/model_presets.txt)
  if [ -n "$hits" ]; then items+=($hits); else items+=("$w"); fi
done

copy_one() {
  local rel="$1" t0 t1 sz
  t0=$(date +%s)
  if [[ "$rel" == */ ]]; then
    mkdir -p "$DST/$rel" && cp -r "$SRC/$rel." "$DST/$rel" 2>/dev/null
  else
    [ -f "$SRC/$rel" ] || { echo "ABSENT $rel" >> "$LOG"; return; }
    mkdir -p "$DST/$(dirname "$rel")"
    [ -f "$DST/$rel" ] && [ "$(stat -c %s "$DST/$rel")" = "$(stat -c %s "$SRC/$rel")" ] && { echo "DEJA $rel" >> "$LOG"; return; }
    cp "$SRC/$rel" "$DST/$rel.part" && mv "$DST/$rel.part" "$DST/$rel"
  fi
  t1=$(date +%s); sz=$(du -sm "$DST/$rel" 2>/dev/null | cut -f1)
  echo "OK $rel ${sz} Mo $((t1-t0))s" >> "$LOG"
}
export -f copy_one; export SRC DST LOG

T0=$(date +%s)
printf '%s\n' "${items[@]}" | sort -u | xargs -P 4 -I{} bash -c 'copy_one "$@"' _ {}
echo "TOTAL $(( $(date +%s)-T0 ))s $(du -sh "$DST" | cut -f1)" >> "$LOG"
touch "$DST/.preload_done"
