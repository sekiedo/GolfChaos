#!/usr/bin/env bash
# Verification locale sans Studio : construction Rojo + analyse de types Luau (luau-lsp, definitions Roblox).
#   scripts/verifier.sh            compare a la reference (build/analyse_reference.txt) et liste les NOUVEAUX diagnostics
#   scripts/verifier.sh --reference   enregistre l'etat courant comme reference
# Outils attendus dans tools/ : rojo.exe (scripts/install-tools.ps1), luau-lsp.exe et globalTypes.d.luau
# (https://github.com/JohnnyMorganz/luau-lsp). Ne remplace PAS un test dans Roblox Studio.
set -u
cd "$(dirname "$0")/.."
mkdir -p build
./tools/rojo.exe build default.project.json -o build/GolfChaos_src.rbxlx >/dev/null || { echo "ECHEC rojo build"; exit 1; }
./tools/rojo.exe sourcemap default.project.json -o sourcemap.json >/dev/null || { echo "ECHEC sourcemap"; exit 1; }
./tools/luau-lsp.exe analyze --sourcemap sourcemap.json --defs=@roblox=tools/globalTypes.d.luau --platform roblox \
  --flag:LuauSolverV2=false --formatter plain src 2>&1 \
  | grep -E '^[^ ].*\.luau' | tr '\134' '/' | sed -E 's@^.*/src/@src/@; s@ \[game/[^]]*\]@@g' > build/analyse_courante.txt
# Forme normalisee sans numero de ligne : "fichier | message"
norm() { sed -E 's#^([^:]+):[0-9]+:[0-9]+-[0-9]+: #\1 | #' "$1" | sort; }
if [ "${1:-}" = "--reference" ]; then
  cp build/analyse_courante.txt build/analyse_reference.txt
  echo "Reference enregistree : $(wc -l < build/analyse_reference.txt) diagnostics"
  exit 0
fi
echo "Construction Rojo : OK"
echo "Diagnostics : $(wc -l < build/analyse_courante.txt) (reference : $(wc -l < build/analyse_reference.txt 2>/dev/null || echo '?'))"
if [ -f build/analyse_reference.txt ]; then
  norm build/analyse_reference.txt > build/.ref.tmp; norm build/analyse_courante.txt > build/.cur.tmp
  nouveaux=$(comm -13 build/.ref.tmp build/.cur.tmp)
  if [ -n "$nouveaux" ]; then
    echo "NOUVEAUX diagnostics :"; echo "$nouveaux" | while IFS= read -r l; do f="${l%% | *}"; m="${l#* | }"; grep -F "$f" build/analyse_courante.txt | grep -F -- "$m" | head -1; done
  else
    echo "Aucun nouveau diagnostic."
  fi
  rm -f build/.ref.tmp build/.cur.tmp
fi
