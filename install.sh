#!/usr/bin/env bash
# Instala a barra de status no Claude Code do usuário atual:
# copia statusline.sh para ~/.claude/ e liga o statusLine no ~/.claude/settings.json.
# Guarda backup (.bak) do que existia antes e não mexe em nenhuma outra chave do settings.
#
#   ./install.sh            instala (ou atualiza)
#   ./install.sh --remover  desliga a barra e apaga ~/.claude/statusline.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
src="$here/statusline.sh"
dest="$HOME/.claude/statusline.sh"
settings="$HOME/.claude/settings.json"
cmd="bash ~/.claude/statusline.sh"

command -v jq >/dev/null || { echo "erro: jq não encontrado (Linux: apt install jq · macOS: brew install jq)" >&2; exit 1; }

# Grava o settings.json via jq, com backup; cat em vez de mv para manter as permissões do arquivo
edit_settings() {
  cp "$settings" "$settings.bak"
  local tmp
  tmp=$(mktemp)
  jq "$@" "$settings" > "$tmp"
  cat "$tmp" > "$settings"
  rm -f "$tmp"
}

# ── Remover ──
if [ "${1:-}" = "--remover" ]; then
  if [ -f "$settings" ] && [ "$(jq -r '.statusLine.command // ""' "$settings")" = "$cmd" ]; then
    edit_settings 'del(.statusLine)'
    echo "statusLine removido de $settings (backup em $settings.bak)"
  else
    echo "o settings.json não aponta para esta barra; nada a desligar"
  fi
  [ -f "$dest" ] && rm -f "$dest" && echo "apagado: $dest"
  exit 0
fi

command -v git >/dev/null || echo "aviso: git não encontrado; repo e branch não vão aparecer" >&2
bash -n "$src"

mkdir -p "$HOME/.claude"

# ── Script ──
[ -f "$dest" ] && cp "$dest" "$dest.bak"
install -m 755 "$src" "$dest"

# ── settings.json ──
[ -f "$settings" ] || echo '{}' > "$settings"
old=$(jq -r '.statusLine.command // ""' "$settings")
[ -n "$old" ] && [ "$old" != "$cmd" ] && echo "aviso: substituindo o statusLine anterior ($old); ele fica guardado no backup"
edit_settings --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd, padding: 0}'

echo "instalado: $dest"
echo "settings:  $settings (backup em $settings.bak)"

# ── Prévia ──
if [ -f "$here/exemplos/entrada.json" ]; then
  echo
  echo "prévia (com dados de exemplo):"
  bash "$dest" < "$here/exemplos/entrada.json"
  echo
fi
echo
echo "a barra aparece na próxima resposta do Claude Code"
