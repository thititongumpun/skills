#!/usr/bin/env bash
# Which skills in this repo actually work on this machine, and what's missing.
# Usage: doctor.sh [--fix] [--selftest]
set -uo pipefail

PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  grep -qi microsoft /proc/version 2>/dev/null && OS=wsl || OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) OS=win ;;
  *)      OS=linux ;;
esac

# name|hard|skills it affects|what breaks without it
DEPS=$(cat <<'EOF'
node|hard|whiteboard|canvas server won't start
curl|hard|fetch-403|rung 1 can't run at all
officecli|hard|pptx-diagram|entire skill is dead, zero fallback
markdown|soft|fetch-403|pages come back as raw HTML instead of markdown
gh|soft|fetch-403|no GitHub-API rung for private repo URLs
browser|soft|whiteboard|the canvas needs an open tab to convert or export
excalidraw|soft|whiteboard|no adjustable canvas; degrades to a mermaid fence
superpowers|soft|autopilot|its planner/reviewer can't invoke brainstorming or systematic-debugging
context7|soft|kafka admin+developer, autopilot, yolo, fetch-403, pptx-diagram|version-pinned library docs; falls back to fetching pages
confluent|soft|confluent-kafka-admin, confluent-kafka-developer|emitted CLI commands go unverified
terraform|soft|confluent-kafka-admin|can't fmt/validate the TF it writes
rtk|soft|autopilot, yolo|shell calls aren't token-optimized
EOF
)

have() {
  case "$1" in
    markdown)    python3 -c 'import html2text' 2>/dev/null || command -v uvx >/dev/null 2>&1 ;;
    browser)     for b in xdg-open wslview open explorer.exe; do
                   command -v "$b" >/dev/null 2>&1 && return 0
                 done; return 1 ;;
    # ponytail: presence check only — a registered-but-broken server reads as
    # present. Fine for an advisory row; upgrade to a real parse if it misleads.
    excalidraw)  grep -qs 'mcp-excalidraw-server' "$HOME/.claude.json" .mcp.json 2>/dev/null ;;
    superpowers) grep -qs '"superpowers@' "$PLUGINS" ;;
    context7)    grep -qs 'context7' "$PLUGINS" "$HOME/.claude.json" .mcp.json 2>/dev/null ;;
    *)           command -v "$1" >/dev/null 2>&1 ;;
  esac
}

fix_for() {
  case "$1" in
    node)      case $OS in mac) echo "brew install node" ;; win) echo "scoop install nodejs" ;;
                           *) echo "https://nodejs.org — or your distro's package manager" ;; esac ;;
    curl)      case $OS in mac) echo "brew install curl" ;; *) echo "sudo apt install curl" ;; esac ;;
    officecli) case $OS in mac) echo "brew install officecli" ;; win) echo "scoop install officecli" ;;
                           *) echo "npm install -g @officecli/officecli" ;; esac ;;
    markdown)  echo "uv tool install html2text  (or: pip install html2text)" ;;
    gh)        case $OS in mac) echo "brew install gh" ;; win) echo "scoop install gh" ;;
                           *) echo "sudo apt install gh" ;; esac ;;
    browser)   case $OS in wsl) echo "sudo apt install wslu" ;;
                           *) echo "install a desktop browser, or open the URL manually" ;; esac ;;
    excalidraw)  echo "claude mcp add excalidraw --scope user -- npx -y mcp-excalidraw-server" ;;
    superpowers) echo "/plugin install superpowers@claude-plugins-official" ;;
    context7)    echo "/plugin install context7@claude-plugins-official" ;;
    confluent) echo "https://docs.confluent.io/confluent-cli/current/install.html" ;;
    terraform) echo "https://developer.hashicorp.com/terraform/install" ;;
    rtk)       echo "optional; skip unless you already use rtk" ;;
  esac
}

# Only user-prefix package managers get run. Everything else is printed.
runnable() {
  case "$1" in
    brew*|npm*|scoop*|"uv tool"*) return 0 ;;
    *) return 1 ;;
  esac
}

selftest() {
  have curl || { echo "selftest FAILED: curl should be found"; exit 1; }
  have __definitely_not_a_binary__ && { echo "selftest FAILED: bogus name should miss"; exit 1; }
  echo "selftest ok"; exit 0
}

FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    --selftest) selftest ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "unknown argument: $a" >&2; exit 2 ;;
  esac
done

dead=() degraded=() ok=()
while IFS='|' read -r name hard skills why; do
  [ -z "$name" ] && continue
  if have "$name"; then
    ok+=("$name")
  elif [ "$hard" = hard ]; then
    dead+=("$name|$skills|$why")
  else
    degraded+=("$name|$skills|$why")
  fi
done <<< "$DEPS"

echo
echo "skills doctor — $OS"
echo

show() {
  local header=$1; shift
  [ $# -eq 0 ] && return
  echo "$header"
  for row in "$@"; do
    IFS='|' read -r name skills why <<< "$row"
    printf '  %-12s %s: %s\n' "$name" "$skills" "$why"
    printf '  %-12s   %s\n' "" "$(fix_for "$name")"
  done
  echo
}

show "DEAD — the skill will not run:" "${dead[@]+"${dead[@]}"}"
show "DEGRADED — the skill runs, worse:" "${degraded[@]+"${degraded[@]}"}"
[ ${#ok[@]} -gt 0 ] && { echo "OK: ${ok[*]}"; echo; }

cat <<'EOF'
Can't be checked from a shell: subagents, AskUserQuestion, TodoWrite,
Artifact, WebFetch/WebSearch. They exist in Claude Code, which is why
autopilot, yolo, and whiteboard's explain mode are Claude Code only.
Run /skills-doctor inside Claude Code to have those checked for real.
EOF
echo

if [ $FIX -eq 1 ]; then
  # No terminal to prompt at (piped, CI, a hook) — print everything, run nothing.
  # Must actually open /dev/tty: with no controlling terminal the node still
  # exists and passes -r, then fails at open with ENXIO.
  tty_ok=1; { : < /dev/tty; } 2>/dev/null || tty_ok=0
  [ $tty_ok -eq 0 ] && echo "No terminal to prompt at — printing every command instead of offering to run it."
  ran=0 refused=0
  for row in "${dead[@]+"${dead[@]}"}" "${degraded[@]+"${degraded[@]}"}"; do
    IFS='|' read -r name _ _ <<< "$row"
    cmd=$(fix_for "$name")
    if runnable "$cmd" && [ $tty_ok -eq 1 ]; then
      printf 'run: %s  [y/N] ' "$cmd"
      { read -r reply < /dev/tty; } 2>/dev/null || reply=n
      case "$reply" in [yY]*) eval "$cmd" && ran=$((ran+1)) ;; esac
    else
      printf 'you run this one: %s\n' "$cmd"
      refused=$((refused+1))
    fi
  done
  echo
  [ $tty_ok -eq 1 ] && [ $ran -eq 0 ] && [ $refused -gt 0 ] &&
    echo "Nothing installed. The ones above marked 'you run this one' need sudo, a shell pipe, or a slash command — those are yours."
fi

n_dead=${#dead[@]} n_deg=${#degraded[@]}
if [ "$n_dead" -gt 0 ]; then
  echo "$n_dead dead, $n_deg degraded.$([ $FIX -eq 0 ] && echo '  --fix to install what is safe.')"
  exit 1
fi
echo "Nothing dead, $n_deg degraded.$([ $n_deg -gt 0 ] && [ $FIX -eq 0 ] && echo '  --fix to install what is safe.')"
exit 0
