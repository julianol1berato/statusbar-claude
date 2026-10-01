#!/usr/bin/env bash
# statusbar-claude-schulze · barra de status do Claude Code
# https://github.com/SchulzeTecnologia/statusbar-claude-schulze
#
# O Claude Code roda este script a cada resposta, com os dados da sessão em JSON na entrada
# padrão, e mostra a linha que ele imprimir. Para ser rápido, só abre dois processos (jq e git);
# o resto usa comandos internos do bash, sem subshells. Compatível com bash 3.2 e jq 1.6+.

LC_ALL=C   # printf com ponto decimal em qualquer idioma do sistema

# ── Aparência ────────────────────────────────────────────────────────────────
E=$'\033['
RST="${E}0m" NEGRITO="${E}1m" APAGADO="${E}2m"
VERMELHO="${E}31m" VERDE="${E}32m" AMARELO="${E}33m" ROXO="${E}35m" CIANO="${E}36m"
VAZIO="${E}38;2;60;60;60m"     # blocos ainda não usados da barra

SEP=" ${APAGADO}|${RST} "      # entre as partes da linha
LARGURA=20                     # blocos da barra de contexto

# Degradê da barra: grupos de 4 números = posição (0–100), vermelho, verde, azul.
# Entre dois pontos a cor é interpolada.
DEGRADE=(0 0 200 80   50 220 200 0   100 220 40 20)

# Emoji do contexto: pares "a partir de quantos %" e emoji, do maior para o menor
EMOJIS=(90 🚨   70 🔥   20 ⚡   0 🟢)

# ── Funções (gravam o resultado na variável cujo nome vem no último argumento) ──

# Percentual arredondado e colorido: verde, amarelo a partir de 70, vermelho a partir de 90
pct() {
  local p cor=$VERDE
  printf -v p '%.0f' "$1" 2>/dev/null || p=0
  (( p >= 70 )) && cor=$AMARELO
  (( p >= 90 )) && cor=$VERMELHO
  printf -v "$2" '%s%s%%%s' "$cor" "$p" "$RST"
}

# Tokens abreviados: 940 → 940 · 94140 → 94k · 200000 → 200k · 1000000 → 1M · 1500000 → 1.5M
abrevia() {
  local n=${1%.*} d
  case $n in ''|*[!0-9]*) n=0 ;; esac   # só dígitos entram na conta (o bash avalia texto em (( )))
  if (( n >= 999500 )); then
    d=$(( (n + 50000) / 100000 ))   # décimos de milhão
    if (( d % 10 )); then printf -v "$2" '%d.%dM' $(( d / 10 )) $(( d % 10 ))
    else printf -v "$2" '%dM' $(( d / 10 )); fi
  elif (( n >= 1000 )); then printf -v "$2" '%dk' $(( (n + 500) / 1000 ))
  else printf -v "$2" '%d' "$n"; fi
}

# ── Dados da sessão: um jq lê tudo, valida os tipos e já converte os horários ───
# Campos separados por \x1f, que não é espaço, para o read manter os vazios no lugar.
# Um campo ausente ou com tipo inesperado vira vazio, sem derrubar os outros.
IFS=$'\x1f' read -r modelo ctx_pct custo mais menos pasta \
  h5_pct d7_pct h5_reset d7_reset ctx_tokens ctx_total effort <<< "$(jq -r '
  def campo(f): try f catch null;
  def num(f): try (f | tonumber) catch null;
  def texto(f): campo(f) | strings | explode | map(select(. >= 32 and (. < 127 or . > 159))) | implode;
  def quando($fmt): try (tonumber | floor | localtime | strflocaltime($fmt)) catch "";
  def hoje: now | quando("%Y-%m-%d");
  [ texto(.model.display_name) // "Unknown",
    num(.context_window.used_percentage) // "",
    num(.cost.total_cost_usd) // 0,
    num(.cost.total_lines_added) // 0,
    num(.cost.total_lines_removed) // 0,
    (campo(.workspace.current_dir) // campo(.cwd) | strings | select(explode | all(. >= 32 and . != 127))) // "",
    num(.rate_limits.five_hour.used_percentage) // "",
    num(.rate_limits.seven_day.used_percentage) // "",
    (campo(.rate_limits.five_hour.resets_at) | if . then quando("%H:%M") else "" end),
    (campo(.rate_limits.seven_day.resets_at)
       | if . then (if quando("%Y-%m-%d") == hoje then quando("%H:%M") else quando("%d/%m") end) else "" end),
    num(.context_window.total_input_tokens) // "",
    num(.context_window.context_window_size) // "",
    texto(.effort.level) // ""
  ] | map(tostring) | join("\u001f")')"
effort=${effort%$'\r'}   # jq.exe no Windows termina a linha com \r\n

# ── Repositório e branch ─────────────────────────────────────────────────────
# Um git devolve a raiz do repositório e a branch. Com HEAD solto ou num repositório
# ainda sem commits ele responde "HEAD"; só nesses casos roda um segundo git.
repo='' branch=''
if [[ -n $pasta ]]; then
  git_out=$(git -C "$pasta" --no-optional-locks rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null)
  if [[ -n $git_out ]]; then
    raiz=${git_out%%$'\n'*}
    repo=${raiz##*/}
    [[ $git_out == *$'\n'* ]] && branch=${git_out#*$'\n'}
    [[ $branch == HEAD ]] && branch=$(git -C "$pasta" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null)
    repo=${repo//[[:cntrl:]]/} branch=${branch//[[:cntrl:]]/}   # nome de pasta pode ter ESC
  fi
fi

# ── Contexto ─────────────────────────────────────────────────────────────────
if [[ -n $ctx_pct ]]; then
  printf -v usado '%.0f' "$ctx_pct"
  cheios=$(( (usado * LARGURA + 50) / 100 ))

  barra=''
  for (( i = 0; i < LARGURA; i++ )); do
    if (( i >= cheios )); then barra+="${VAZIO}░"; continue; fi
    pos=$(( i * 100 / (LARGURA - 1) ))
    j=0   # início do trecho do degradê onde a posição cai
    while (( j + 8 < ${#DEGRADE[@]} && pos > DEGRADE[j + 4] )); do (( j += 4 )); done
    p0=${DEGRADE[j]} dp=$(( DEGRADE[j + 4] - DEGRADE[j] ))
    r=$(( DEGRADE[j + 1] + (DEGRADE[j + 5] - DEGRADE[j + 1]) * (pos - p0) / dp ))
    g=$(( DEGRADE[j + 2] + (DEGRADE[j + 6] - DEGRADE[j + 2]) * (pos - p0) / dp ))
    b=$(( DEGRADE[j + 3] + (DEGRADE[j + 7] - DEGRADE[j + 3]) * (pos - p0) / dp ))
    barra+="${E}38;2;${r};${g};${b}m█"
  done
  barra+=$RST

  emoji=${EMOJIS[${#EMOJIS[@]} - 1]}
  for (( k = 0; k < ${#EMOJIS[@]}; k += 2 )); do
    (( usado >= EMOJIS[k] )) && { emoji=${EMOJIS[k + 1]}; break; }
  done

  usado_txt='' t1='' t2=''
  pct "$ctx_pct" usado_txt
  ctx="$emoji $barra $usado_txt"
  if [[ -n $ctx_tokens && -n $ctx_total ]]; then
    abrevia "$ctx_tokens" t1
    abrevia "$ctx_total" t2
    ctx+=" ${APAGADO}${t1}/${t2}${RST}"
  fi
else
  printf -v vazios '%*s' "$LARGURA" ''
  ctx="${EMOJIS[${#EMOJIS[@]} - 1]} ${VAZIO}${vazios// /░}${RST} --%"
fi

# ── Limites de 5h / 7d (só Pro/Max, depois da primeira resposta) ─────────────────
limites='' t=''
if [[ -n $h5_pct ]]; then
  pct "$h5_pct" t
  limites="5h $t"
  [[ -n $h5_reset ]] && limites+=" ${APAGADO}↻${h5_reset}${RST}"
fi
if [[ -n $d7_pct ]]; then
  pct "$d7_pct" t
  t="7d $t"
  [[ -n $d7_reset ]] && t+=" ${APAGADO}↻${d7_reset}${RST}"
  limites="${limites:+$limites ${APAGADO}·${RST} }$t"
fi

# ── Custo, linhas e modelo ───────────────────────────────────────────────────
printf -v custo_txt '%s$%.2f%s' "$AMARELO" "${custo:-0}" "$RST"
linhas="${VERDE}+${mais}${RST} ${VERMELHO}-${menos}${RST}"
modelo_txt="${ROXO}🤖 ${modelo}${effort:+ ($effort)}${RST}"

# ── Linha final: as partes vazias ficam de fora ─────────────────────────────────
cabeca=''
[[ -n $repo ]] && cabeca="${NEGRITO}${AMARELO}${repo}${RST}"
[[ -n $branch ]] && cabeca="${cabeca:+$cabeca }${NEGRITO}${CIANO}🌿 (${branch})${RST}"

linha=''
for parte in "$cabeca" "$ctx" "$limites" "$custo_txt" "$linhas" "$modelo_txt"; do
  [[ -n $parte ]] && linha+="${linha:+$SEP}$parte"
done
printf '%s' "$linha"
