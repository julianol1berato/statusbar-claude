#!/usr/bin/env bash
# Testes da barra: roda o statusline.sh em vários cenários e compara, byte a byte, com a saída
# esperada em testes/esperado.txt (cores aparecem como \e para o diff ficar legível).
#
#   testes/rodar.sh              roda os testes
#   testes/rodar.sh --atualizar  regrava testes/esperado.txt; use só depois de conferir a mudança
set -u

raiz="$(cd "$(dirname "$0")/.." && pwd)"
script="$raiz/statusline.sh"
esperado="$raiz/testes/esperado.txt"
base="$raiz/exemplos/entrada.json"

export TZ='<-03>3'      # fuso fixo (UTC-3, sem horário de verão), sem depender do tzdata
export LC_ALL=C

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ── Repositórios de teste ──
g() { git -c user.name=teste -c user.email=teste@exemplo -c init.defaultBranch=main "$@"; }
g init -q "$tmp/repo-teste" && g -C "$tmp/repo-teste" commit -q --allow-empty -m inicial
g -C "$tmp/repo-teste" checkout -q -b feature/barra
g init -q "$tmp/repo-vazio"
g init -q "$tmp/repo-solto" && g -C "$tmp/repo-solto" commit -q --allow-empty -m inicial && g -C "$tmp/repo-solto" checkout -q --detach
mkdir -p "$tmp/sem-git" "$tmp/repo-teste/sub/pasta"

# Reset de 7d às 23:59 de hoje no fuso acima, para testar o caso "zera hoje" sem depender da hora
agora=$(date +%s)
hoje_2359=$(( (agora - 10800) / 86400 * 86400 + 86340 + 10800 ))

# Base de todos os cenários: o exemplo, na pasta do repo de teste e com reset de 7d numa data fixa
fixa=".workspace.current_dir = \"$tmp/repo-teste\" | .rate_limits.seven_day.resets_at = 1700000000"

# ── Cenários: nome | filtro jq aplicado sobre a base ──
cenarios=$(cat <<EOF
exemplo completo|.
contexto 0%|.context_window.used_percentage = 0
contexto 19%|.context_window.used_percentage = 19
contexto 20%|.context_window.used_percentage = 20
contexto 69%|.context_window.used_percentage = 69
contexto 70%|.context_window.used_percentage = 70
contexto 89%|.context_window.used_percentage = 89
contexto 90%|.context_window.used_percentage = 90
contexto 100%|.context_window.used_percentage = 100
contexto acima de 100%|.context_window.used_percentage = 130
contexto com decimais|.context_window.used_percentage = 47.6
contexto ausente|.context_window.used_percentage = null
sem context_window|del(.context_window)
sem tamanho da janela|del(.context_window.context_window_size)
tokens 999|.context_window.total_input_tokens = 999
tokens 1500|.context_window.total_input_tokens = 1500
tokens 999499|.context_window.total_input_tokens = 999499
tokens 999700|.context_window.total_input_tokens = 999700
tokens 1500000|.context_window.total_input_tokens = 1500000
janela 200k|.context_window.context_window_size = 200000
sem limites|del(.rate_limits)
só 5h|del(.rate_limits.seven_day)
só 7d|del(.rate_limits.five_hour)
5h sem horário|del(.rate_limits.five_hour.resets_at)
7d zera hoje|.rate_limits.seven_day.resets_at = $hoje_2359
limites amarelo e vermelho|.rate_limits.five_hour.used_percentage = 69.5 | .rate_limits.seven_day.used_percentage = 89.6
sem effort|del(.effort)
sem modelo|del(.model)
custo longo|.cost.total_cost_usd = 1234.56789
sem cost|del(.cost)
só cwd|del(.workspace) | .cwd = "$tmp/repo-teste"
sem pasta|del(.workspace) | del(.cwd)
pasta inexistente|.workspace.current_dir = "/nao/existe"
fora de repositório|.workspace.current_dir = "$tmp/sem-git"
subpasta do repositório|.workspace.current_dir = "$tmp/repo-teste/sub/pasta"
repositório sem commits|.workspace.current_dir = "$tmp/repo-vazio"
HEAD solto|.workspace.current_dir = "$tmp/repo-solto"
EOF
)

saidas=""
while IFS='|' read -r nome filtro; do
  out=$(jq "$fixa | $filtro" "$base" | bash "$script" 2>&1 | sed $'s/\x1b/\\\\e/g')
  saidas+="$nome: $out"$'\n'
done <<< "$cenarios"

if [ "${1:-}" = "--atualizar" ]; then
  printf '%s' "$saidas" > "$esperado"
  echo "regravado: $esperado ($(wc -l < "$esperado" | tr -d ' ') cenários)"
  exit 0
fi

if diff -u --label esperado --label obtido "$esperado" <(printf '%s' "$saidas"); then
  falhas=0
else
  falhas=1
fi
total=$(printf '%s' "$saidas" | wc -l | tr -d ' ')

# Tempo médio por execução (informativo; precisa do relógio de microssegundos do bash 5)
tempo=""
if [ -n "${EPOCHREALTIME:-}" ]; then
  jq "$fixa" "$base" > "$tmp/in.json"
  ini=${EPOCHREALTIME/./}
  for (( i = 0; i < 20; i++ )); do bash "$script" < "$tmp/in.json" > /dev/null; done
  tempo=" · $(( (${EPOCHREALTIME/./} - ini) / 20000 )) ms por execução"
fi

if (( falhas )); then
  echo "FALHOU: a saída mudou (diff acima)$tempo"
  exit 1
fi
echo "ok: $total cenários idênticos ao esperado$tempo"
