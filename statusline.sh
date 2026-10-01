#!/usr/bin/env bash
# Claude Code status line: RGB gradient, dynamic emoji, context tokens, rate limits with reset time,
# cost, code velocity, model + effort

input=$(cat)

# ── Colors ──
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Truecolor helper ──
rgb() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }

# ── Parse JSON fields ──
# A single jq call (one per field costs ~12ms each). Fields are joined with \x1f, a
# non-whitespace separator, so `read` keeps empty fields in place.
IFS=$'\x1f' read -r model used cost lines_add lines_del cwd \
  five_hr seven_day five_hr_reset seven_day_reset ctx_tokens ctx_size effort <<< "$(
  echo "$input" | jq -r '[
    .model.display_name // "Unknown",
    .context_window.used_percentage // "",
    .cost.total_cost_usd // 0,
    .cost.total_lines_added // 0,
    .cost.total_lines_removed // 0,
    .workspace.current_dir // .cwd // "",
    .rate_limits.five_hour.used_percentage // "",
    .rate_limits.seven_day.used_percentage // "",
    .rate_limits.five_hour.resets_at // "",
    .rate_limits.seven_day.resets_at // "",
    .context_window.total_input_tokens // "",
    .context_window.context_window_size // "",
    .effort.level // ""
  ] | map(tostring) | join("\u001f")'
)"

# ── Git info ──
branch=""
repo=""
if [ -n "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  repo=$(basename "$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
fi

# ── Formatting helpers ──
# 94140 -> 94k, 200000 -> 200k, 1000000 -> 1M, 1500000 -> 1.5M
fmt_tokens() {
  local n=${1%.*}
  if [ "$n" -ge 1000000 ]; then
    if [ $(( n % 1000000 )) -eq 0 ]; then printf '%dM' $(( n / 1000000 ))
    else printf '%d.%dM' $(( n / 1000000 )) $(( n % 1000000 / 100000 )); fi
  elif [ "$n" -ge 1000 ]; then printf '%dk' $(( (n + 500) / 1000 ))
  else printf '%d' "$n"; fi
}

# Epoch seconds -> local time (GNU date, falling back to BSD/macOS date)
fmt_epoch() { date -d "@${1%.*}" +"$2" 2>/dev/null || date -r "${1%.*}" +"$2"; }

# ── Context bar: RGB gradient, full blocks only ──
BAR_WIDTH=20

if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")

  # Round to nearest block
  filled=$(( (used_int * BAR_WIDTH + 50) / 100 ))

  bar=""
  for (( i=0; i<BAR_WIDTH; i++ )); do
    pos=$(( i * 100 / (BAR_WIDTH - 1) ))

    if [ "$pos" -le 50 ]; then
      r=$(( 0 + 220 * pos / 50 ))
      g=200
      b=$(( 80 - 80 * pos / 50 ))
    else
      adj=$(( pos - 50 ))
      r=220
      g=$(( 200 - 160 * adj / 50 ))
      b=$(( 0 + 20 * adj / 50 ))
    fi

    if [ "$i" -lt "$filled" ]; then
      bar="${bar}$(rgb $r $g $b)█"
    else
      bar="${bar}\033[38;2;60;60;60m░"
    fi
  done
  bar="${bar}${RESET}"

  if [ "$used_int" -ge 90 ]; then status_emoji="🚨"
  elif [ "$used_int" -ge 70 ]; then status_emoji="🔥"
  elif [ "$used_int" -ge 20 ]; then status_emoji="⚡"
  else status_emoji="🟢"; fi

  if [ "$used_int" -ge 90 ]; then pct_color="$RED"
  elif [ "$used_int" -ge 70 ]; then pct_color="$YELLOW"
  else pct_color="$GREEN"; fi

  ctx_part="${status_emoji} ${bar} ${pct_color}${used_int}%${RESET}"
  [ -n "$ctx_tokens" ] && [ -n "$ctx_size" ] && \
    ctx_part="${ctx_part} ${DIM}$(fmt_tokens "$ctx_tokens")/$(fmt_tokens "$ctx_size")${RESET}"
else
  ctx_part="🟢 \033[38;2;60;60;60m░░░░░░░░░░░░░░░░░░░░${RESET} --%"
fi

# ── Rate limits (Pro/Max only; absent until the first API response) ──
pct_colored() {
  local p
  p=$(printf '%.0f' "$1")
  if [ "$p" -ge 90 ]; then printf '%s' "${RED}${p}%${RESET}"
  elif [ "$p" -ge 70 ]; then printf '%s' "${YELLOW}${p}%${RESET}"
  else printf '%s' "${GREEN}${p}%${RESET}"; fi
}

limits_part=""
if [ -n "$five_hr" ]; then
  limits_part="5h $(pct_colored "$five_hr")"
  [ -n "$five_hr_reset" ] && limits_part="${limits_part} ${DIM}↻$(fmt_epoch "$five_hr_reset" '%H:%M')${RESET}"
fi
if [ -n "$seven_day" ]; then
  seven_part="7d $(pct_colored "$seven_day")"
  if [ -n "$seven_day_reset" ]; then
    # Resets today: show the time; otherwise the date
    fmt='%d/%m'
    [ "$(fmt_epoch "$seven_day_reset" '%F')" = "$(date +%F)" ] && fmt='%H:%M'
    seven_part="${seven_part} ${DIM}↻$(fmt_epoch "$seven_day_reset" "$fmt")${RESET}"
  fi
  limits_part="${limits_part:+$limits_part ${DIM}·${RESET} }${seven_part}"
fi

# ── Cost ──
cost_part="${YELLOW}$(printf '$%.2f' "$cost")${RESET}"

# ── Code velocity ──
velocity="${GREEN}+${lines_add}${RESET} ${RED}-${lines_del}${RESET}"

# ── Single line ──
out=""
[ -n "$repo" ] && out="${BOLD}${YELLOW}${repo}${RESET}"
[ -n "$branch" ] && out="${out:+$out }${BOLD}${CYAN}🌿 (${branch})${RESET}"
out="${out:+$out ${DIM}|${RESET} }${ctx_part}"
[ -n "$limits_part" ] && out="${out} ${DIM}|${RESET} ${limits_part}"
out="${out} ${DIM}|${RESET} ${cost_part}"
out="${out} ${DIM}|${RESET} ${velocity}"
if [ -n "$effort" ]; then
  out="${out} ${DIM}|${RESET} ${MAGENTA}🤖 ${model} (${effort})${RESET}"
else
  out="${out} ${DIM}|${RESET} ${MAGENTA}🤖 ${model}${RESET}"
fi

printf '%b' "$out"
