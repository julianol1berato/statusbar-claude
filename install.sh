#!/usr/bin/env bash
# Instala a barra de status no Claude Code do usuário atual: copia statusline.sh para ~/.claude/
# e liga o statusLine no ~/.claude/settings.json, sem mexer nas outras chaves. Antes de
# sobrescrever algo que não seja desta barra, guarda uma cópia com data e hora no nome.
#
#   ./install.sh            instala ou atualiza
#   ./install.sh --remover  desliga a barra e apaga ~/.claude/statusline.sh
#   ./install.sh --ajuda    mostra esta ajuda
set -euo pipefail

uso() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; }
erro() { echo "erro: $*" >&2; exit 1; }

acao=instalar
if [ $# -gt 1 ]; then uso >&2; exit 2; fi
case ${1:-} in
  '') ;;
  --remover) acao=remover ;;
  -h|--help|--ajuda) uso; exit 0 ;;
  *) echo "opção desconhecida: $1" >&2; uso >&2; exit 2 ;;
esac

aqui=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
src="$aqui/statusline.sh"
dir="$HOME/.claude"
dest="$dir/statusline.sh"
settings="$dir/settings.json"
cmd="bash ~/.claude/statusline.sh"
carimbo=$(date +%Y%m%d-%H%M%S)

tmp=''
trap 'if [ -n "$tmp" ]; then rm -f "$tmp"; fi' EXIT

command -v jq >/dev/null || erro "jq não encontrado (Linux: apt install jq · macOS: brew install jq)"
jq -n '0 | localtime | strflocaltime("%H")' >/dev/null 2>&1 \
  || erro "$(jq --version 2>/dev/null) é antigo demais; a barra precisa do jq 1.6 ou mais novo"

# O arquivo é desta barra? Reconhece também a primeira versão, de antes do nome no cabeçalho.
e_nossa() {
  [ -f "$1" ] && grep -q -e 'statusbar-claude-schulze' \
    -e '^# Claude Code status line: RGB gradient, dynamic emoji, context tokens' "$1"
}

# Guarda uma cópia com data e hora no nome; nunca sobrescreve um backup anterior
guarda() {
  local bak="$1.bak-$carimbo" n=1
  while [ -e "$bak" ]; do n=$(( n + 1 )); bak="$1.bak-$carimbo-$n"; done
  cp -p "$1" "$bak"
  echo "backup:    $bak"
}

# Conteúdo atual do settings.json. Arquivo ausente ou vazio vale como {}; se não for um
# único objeto JSON, para antes de alterar qualquer coisa.
le_settings() {
  if [ ! -f "$settings" ] || ! grep -q '[^[:space:]]' "$settings"; then echo '{}'; return; fi
  jq -s 'if length == 1 and (.[0] | type) == "object" then .[0] else error("") end' "$settings" 2>/dev/null \
    || erro "$settings não é um objeto JSON válido; veja o problema com: jq . $settings (nada foi alterado)"
}

pode_gravar_settings() {
  if [ -f "$settings" ] && [ ! -w "$settings" ]; then
    erro "sem permissão para alterar $settings (nada foi alterado)"
  fi
}

comando_atual() { jq -r '.statusLine.command? // ""' <<< "$1"; }

# ── Remover ──
if [ "$acao" = remover ]; then
  atual=$(le_settings)
  if [ "$(comando_atual "$atual")" = "$cmd" ]; then
    pode_gravar_settings
    guarda "$settings"
    atual=$(jq 'del(.statusLine)' <<< "$atual")
    printf '%s\n' "$atual" > "$settings"
    echo "desligado: statusLine removido de $settings"
  else
    echo "o settings.json não aponta para esta barra; nada a desligar"
  fi
  if ! e_nossa "$dest"; then
    if [ -f "$dest" ]; then echo "mantido:   $dest (não é desta barra)"; fi
  elif [[ $(comando_atual "$atual") == *statusline.sh* ]]; then
    echo "mantido:   $dest (o settings.json ainda aponta para ele)"
  else
    rm -f "$dest"
    echo "apagado:   $dest"
  fi
  exit 0
fi

# ── Instalar: valida tudo antes de alterar qualquer arquivo ──
[ -f "$src" ] || erro "statusline.sh não encontrado em $aqui"
bash -n "$src"
command -v git >/dev/null || echo "aviso: git não encontrado; repo e branch não vão aparecer" >&2
mkdir -p "$dir"
[ -w "$dir" ] || erro "sem permissão para gravar em $dir"
atual=$(le_settings)
pode_gravar_settings

# Script: troca atômica (cópia temporária + mv), para nenhuma sessão aberta ler um arquivo pela metade
if [ -f "$dest" ] && ! cmp -s "$src" "$dest" && ! e_nossa "$dest"; then guarda "$dest"; fi
tmp=$(mktemp "$dir/.statusline.XXXXXX")
cp "$src" "$tmp"
chmod 755 "$tmp"
mv -f "$tmp" "$dest"
tmp=''
echo "instalado: $dest"

# settings.json: só grava se mudar; cat/printf > mantém permissões e links simbólicos
novo=$(jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd, padding: 0}' <<< "$atual")
if [ -f "$settings" ] && [ "$(jq -cS . <<< "$novo")" = "$(jq -cS . <<< "$atual")" ]; then
  echo "settings:  $settings já estava configurado"
else
  antigo=$(comando_atual "$atual")
  if [ -n "$antigo" ] && [ "$antigo" != "$cmd" ]; then
    echo "aviso: substituindo o statusLine anterior ($antigo)"
  fi
  if [ -f "$settings" ]; then guarda "$settings"; fi
  printf '%s\n' "$novo" > "$settings"
  echo "settings:  $settings"
fi

# ── Prévia ──
if [ -f "$aqui/exemplos/entrada.json" ]; then
  echo
  echo "prévia (com dados de exemplo):"
  bash "$dest" < "$aqui/exemplos/entrada.json"
  echo
fi
echo
echo "a barra aparece na próxima resposta do Claude Code"
