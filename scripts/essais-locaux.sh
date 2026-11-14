#!/usr/bin/env bash
# Execute les tests unitaires (src/tests/Specs) HORS Roblox, avec tools/luau.exe et une emulation minimale des
# API Roblox (scripts/local/prelude.luau). Utile pour les modules purs : logique, donnees, sauvegarde.
#   bash scripts/essais-locaux.sh            tous les specs
#   bash scripts/essais-locaux.sh PlayerData seulement les specs dont le nom contient "PlayerData"
#   VERBEUX=1 bash scripts/essais-locaux.sh  affiche aussi les tests reussis et les avertissements du jeu
# Les specs qui ont besoin du vrai moteur (CFrame, instances reelles) echouent ici : c'est attendu.
# Un test vert ici NE REMPLACE PAS une execution dans Roblox Studio (Runner.run()).
set -u
cd "$(dirname "$0")/.."
mkdir -p build
out=build/bundle.luau
cat scripts/local/prelude.luau > "$out"

for f in $(find src/shared src/server src/tests -name '*.luau' | sort); do
  rel="${f#src/}"
  rel="${rel%.luau}"
  case "$rel" in
    shared/*) path="ReplicatedStorage/Shared/${rel#shared/}" ;;
    server/*) path="ServerScriptService/Server/${rel#server/}" ;;
    tests/*)  path="ServerStorage/Tests/${rel#tests/}" ;;
  esac
  case "$path" in
    */init.server|*/init.client) continue ;;
    */init) path="${path%/init}" ;;
  esac
  printf '\n__register("%s", function(script)\n' "$path" >> "$out"
  # "export type" n'est permis qu'au premier niveau d'un fichier : dans le bundle, chaque module est une fonction.
  sed -E 's/^export type /type /' "$f" >> "$out"
  printf '\nend)\n' >> "$out"
done

filter="nil"
[ -n "${1:-}" ] && filter="\"$1\""
verbose="false"
[ -n "${VERBEUX:-}" ] && verbose="true"
cat >> "$out" <<EOF

__ESSAIS_VERBEUX = $verbose
local Runner = require(game:GetService("ServerStorage").Tests.Runner)
local result = Runner.run($filter, { verbose = $verbose })
if result.failed > 0 then
	error("ESSAIS LOCAUX : " .. result.failed .. " echec(s)", 0)
end
EOF

./tools/luau.exe "$out"
