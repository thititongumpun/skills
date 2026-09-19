#!/usr/bin/env bash
# Which skills in this repo actually work on this machine, and what's missing.
# Usage: doctor.sh [--fix] [--skills] [--selftest]
#   --skills  only the third-party skills this repo's skills route to; silent
#             when all present, exit 2 with the install lines when not (hook mode)
set -uo pipefail

PLUGINS="$HOME/.claude/plugins/installed_plugins.json"

case "$(uname -s)" in
  Darwin) OS=mac ;;
  Linux)  grep -qi microsoft /proc/version 2>/dev/null && OS=wsl || OS=linux ;;
  MINGW*|MSYS*|CYGWIN*) OS=win ;;
  *)      OS=linux ;;
esac

# name|hard|skills it affects|what breaks without it
# ponytail: read -d '' not DEPS=$(cat <<EOF) — bash 3.2 mis-parses apostrophes
# inside a heredoc nested in $( ). Returns 1 at EOF, hence the || true.
IFS= read -r -d '' DEPS <<'EOF' || true
curl|hard|fetch-403, n8n-upgrade|rung 1 can't run at all; n8n-upgrade can't reach the API
docker|hard|n8n-upgrade|can't inspect, pull, or restart the stack
jq|soft|n8n-upgrade|active-workflow diff falls back to raw JSON
officecli|hard|mfec-pptx-diagram|entire skill is dead, zero fallback
python3|soft|mfec-pptx-diagram|no layout gate or flow animation; the diagram still lands
markdown|soft|fetch-403|pages come back as raw HTML instead of markdown
gh|soft|fetch-403|no GitHub-API rung for private repo URLs
headless|soft|mfec-pptx-diagram|no render=image and no screenshot check; render=auto falls back to native
superpowers|soft|autopilot|its planner/reviewer can't invoke brainstorming or systematic-debugging
context7|soft|kafka admin+developer, autopilot, yolo, fetch-403, mfec-pptx-diagram|version-pinned library docs; falls back to fetching pages
confluent|soft|confluent-kafka-admin, confluent-kafka-developer|emitted CLI commands go unverified
terraform|soft|confluent-kafka-admin|can't fmt/validate the TF it writes
ppt-master|soft|mfec-pptx-diagram|whole-deck work has nowhere to route; the diagram slide still lands
archify|soft|explain-repo|no HTML/SVG picture; degrades to a mermaid fence
codegraph|soft|explain-repo|no symbol graph; falls back to reading entrypoints, shallower map
rtk|soft|autopilot, yolo|shell calls aren't token-optimized
EOF

have() {
  case "$1" in
    markdown)    python3 -c 'import html2text' 2>/dev/null || command -v uvx >/dev/null 2>&1 ;;
    # An opener is not a renderer: on WSL explorer.exe passes `browser` while
    # officecli still has nothing to rasterize with. Check for a real binary.
    headless)    for b in google-chrome google-chrome-stable chromium \
                          chromium-browser microsoft-edge firefox; do
                   command -v "$b" >/dev/null 2>&1 && return 0
                 done
                 python3 -c 'import playwright' 2>/dev/null ;;
    superpowers) grep -qs '"superpowers@' "$PLUGINS" ;;
    archify|ppt-master)
                 [ -f "$HOME/.claude/skills/$1/SKILL.md" ] ||
                 [ -f "$HOME/.agents/skills/$1/SKILL.md" ] ;;
    codegraph)   command -v codegraph >/dev/null 2>&1 ||
                 grep -qs 'codegraph' "$HOME/.claude.json" .mcp.json 2>/dev/null ;;
    context7)    grep -qs 'context7' "$PLUGINS" "$HOME/.claude.json" .mcp.json 2>/dev/null ;;
    *)           command -v "$1" >/dev/null 2>&1 ;;
  esac
}

fix_for() {
  case "$1" in
    curl)      case $OS in mac) echo "brew install curl" ;; *) echo "sudo apt install curl" ;; esac ;;
    officecli) case $OS in mac) echo "brew install officecli" ;; win) echo "scoop install officecli" ;;
                           *) echo "npm install -g @officecli/officecli" ;; esac ;;
    markdown)  echo "uv tool install html2text  (or: pip install html2text)" ;;
    gh)        case $OS in mac) echo "brew install gh" ;; win) echo "scoop install gh" ;;
                           *) echo "sudo apt install gh" ;; esac ;;
    headless)  echo "pip install playwright && playwright install chromium  (or install Chrome/Chromium)" ;;
    superpowers) echo "/plugin install superpowers@claude-plugins-official" ;;
    ppt-master) echo "npx skills add hugohe3/ppt-master" ;;
    archify)   echo "https://github.com/tt-a1i/archify — or re-link it into ~/.agents/skills/archify" ;;
    context7)    echo "/plugin install context7@claude-plugins-official" ;;
    codegraph)   echo "npm install -g @colbymchenry/codegraph  (then: codegraph init -i in the repo)" ;;
    confluent) echo "https://docs.confluent.io/confluent-cli/current/install.html" ;;
    terraform) echo "https://developer.hashicorp.com/terraform/install" ;;
    python3)   case $OS in mac) echo "brew install python" ;; win) echo "scoop install python" ;;
                           *) echo "sudo apt install python3" ;; esac ;;
    rtk)       echo "optional; skip unless you already use rtk" ;;
    docker)    echo "https://docs.docker.com/engine/install/" ;;
    jq)        case $OS in mac) echo "brew install jq" ;; win) echo "scoop install jq" ;;
                           *) echo "sudo apt install jq" ;; esac ;;
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

FIX=0 SKILLS=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    --skills) SKILLS=1 ;;
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

# Skills installed from other repos that this repo's skills hand work to.
# Hook mode: say nothing when they're all here, so a healthy session start is quiet.
if [ $SKILLS -eq 1 ]; then
  missing=()
  for row in "${dead[@]+"${dead[@]}"}" "${degraded[@]+"${degraded[@]}"}"; do
    IFS='|' read -r name skills _ <<< "$row"
    case " archify ppt-master superpowers " in
      *" $name "*) missing+=("$name (used by $skills): $(fix_for "$name")") ;;
    esac
  done
  [ ${#missing[@]} -eq 0 ] && exit 0
  { echo "skills-doctor: missing skills this plugin routes to — install before using them:"
    printf '  %s\n' "${missing[@]}"; } | tee /dev/stderr
  exit 2
fi

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
autopilot and yolo are Claude Code only.
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
# bash 3.2 mis-parses a single-quoted string inside $() inside "" — hoist it out
hint=""; [ $FIX -eq 0 ] && hint="  --fix to install what is safe."
if [ "$n_dead" -gt 0 ]; then
  echo "$n_dead dead, $n_deg degraded.$hint"
  exit 1
fi
echo "Nothing dead, $n_deg degraded.$([ $n_deg -gt 0 ] && echo "$hint")"
exit 0
