#!/bin/bash
# Copie du global volume vers le disque local (/models) les modèles demandés.
#   PRELOAD_MODELS="krea"                           -> presets de /opt/model_presets.txt
#   PRELOAD_MODELS="krea vae/autre.safetensors"     -> on peut mélanger presets et chemins
#   PRELOAD_MODELS="none" (ou vide)                 -> aucun modèle
#   Séparateur : espace ou virgule.
#   PRELOAD_LORAS="all" (défaut)  -> tout loras/ (OK à 20 persos, pas à 2 000)
#   PRELOAD_LORAS="none"          -> aucune LoRA
#   PRELOAD_LORAS="character/nv_e4u66d_k2.safetensors lenovo.safetensors" -> seulement celles-là
#                                    (chemins sous loras/, .safetensors optionnel)
# Une copie à la fois (4 en parallèle = I/O error le 04/10), 3 essais par fichier.
# Log : /models/preload.log ; fin : /models/.preload_done
set -u
SRC="$1/models"
DST=/models
mkdir -p "$DST"
LOG="$DST/preload.log"
: > "$LOG"

items=()
LIST="${PRELOAD_MODELS:-none}"
for w in ${LIST//,/ }; do
  [ "$w" = none ] && continue
  hits=$(awk -v p="$w" '$1==p {print $2}' /opt/model_presets.txt)
  if [ -n "$hits" ]; then items+=($hits); else items+=("$w"); fi
done

LORAS="${PRELOAD_LORAS:-all}"
case "$LORAS" in
  all)  items+=("loras/") ;;
  none) ;;
  *)    for l in ${LORAS//,/ }; do
          [[ "$l" == *.safetensors ]] || l="$l.safetensors"
          items+=("loras/$l")
        done ;;
esac

copy_one() {
  local rel="$1" t0 t1 sz n
  t0=$(date +%s)
  if [[ "$rel" == */ ]]; then
    mkdir -p "$DST/$rel" && cp -r "$SRC/$rel." "$DST/$rel" || { echo "ECHEC $rel" >> "$LOG"; return; }
  else
    [ -f "$SRC/$rel" ] || { echo "ABSENT $rel" >> "$LOG"; return; }
    mkdir -p "$DST/$(dirname "$rel")"
    [ -f "$DST/$rel" ] && [ "$(stat -c %s "$DST/$rel")" = "$(stat -c %s "$SRC/$rel")" ] && { echo "DEJA $rel" >> "$LOG"; return; }
    for n in 1 2 3; do
      cp "$SRC/$rel" "$DST/$rel.part" && [ "$(stat -c %s "$DST/$rel.part")" = "$(stat -c %s "$SRC/$rel")" ] \
        && mv "$DST/$rel.part" "$DST/$rel" && break
      rm -f "$DST/$rel.part"; echo "RETRY $n $rel" >> "$LOG"; sleep 5
    done
    [ -f "$DST/$rel" ] || { echo "ECHEC $rel" >> "$LOG"; return; }
  fi
  t1=$(date +%s); sz=$(du -sm "$DST/$rel" 2>/dev/null | cut -f1)
  echo "OK $rel ${sz} Mo $((t1-t0))s $(( sz / (t1-t0>0 ? t1-t0 : 1) )) Mo/s" >> "$LOG"
}

T0=$(date +%s)
for rel in $(printf '%s\n' "${items[@]}" | awk '!seen[$0]++'); do
  copy_one "$rel"
done
echo "TOTAL $(( $(date +%s)-T0 ))s $(du -sh "$DST" | cut -f1)" >> "$LOG"
touch "$DST/.preload_done"
