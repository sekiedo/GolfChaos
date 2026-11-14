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
# Cles de texte ecrites en toutes lettres dans le code mais absentes des fichiers Locale/fr.
grep -rhoE '\["[a-zA-Z]+\.[A-Za-z0-9_.]+"\]' src/shared/Locale/fr | tr -d '[]"' | sort -u > build/.keys_fr.tmp
prefixes=$(cut -d. -f1 build/.keys_fr.tmp | sort -u | paste -sd'|')
absentes=$(grep -rhoE "\"($prefixes)\.[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*\"" src/server src/client src/shared --include=*.luau --exclude-dir=Locale \
  | tr -d '"' | sort -u | comm -23 - build/.keys_fr.tmp | grep -vxE 'menu\.ready|ui\.ok|cos\.head_pirate_hat') # exemples cites dans des commentaires
rm -f build/.keys_fr.tmp
if [ -n "$absentes" ]; then echo "CLES DE TEXTE ABSENTES en francais :"; echo "$absentes"; else echo "Cles de texte : aucune cle utilisee absente."; fi
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
