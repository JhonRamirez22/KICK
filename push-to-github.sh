#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────
# Push del bot a GitHub Actions
# USO: ./push-to-github.sh <tu-usuario> <nombre-repo>
# EJ:  ./push-to-github.sh jhon123 kick-bot
# ──────────────────────────────────────────────────────────────────

USER="${1:-}"
REPO="${2:-kick-bot-private}"

if [[ -z "$USER" ]]; then
  echo "USO: ./push-to-github.sh <usuario> [nombre-repo]"
  exit 1
fi

DIR="$(cd "$(dirname "$0")" && pwd)"

# Git init si no existe
cd "$DIR"
if [[ ! -d .git ]]; then
  git init
  git checkout -b main
fi

# Crear .gitignore
cat > .gitignore << 'GIEOF'
node_modules
logs/
__pycache__/
*.pyc
.venv/
.env
proxies.txt
GIEOF

# Commit
git add -A
git commit -m "kick bot — GitHub Actions con Tor proxy" 2>/dev/null || true

# Crear repo y pushear (requiere gh cli)
git remote remove origin 2>/dev/null || true
gh repo create "$USER/$REPO" --private --source=. --push 2>/dev/null || {
  echo ""
  echo "Si gh no está instalado o autenticado:"
  echo "1. Crea el repo manual en https://github.com/new (privado)"
  echo "2. Luego ejecuta:"
  echo "   git remote add origin git@github.com:$USER/$REPO.git"
  echo "   git push -u origin main"
}

echo ""
echo "✅ Listo! Ve a: https://github.com/$USER/$REPO/actions"
echo "   Click 'Kick Bot' → 'Run workflow' → llena los campos → Run"
