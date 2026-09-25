#!/usr/bin/env bash
# PROTO//GREEN updater - pulls the latest version from GitHub and syncs it into
# ~/.config without touching anything you edited.
#
#   protogreen-update            check GitHub, show what changed, ask, update
#   protogreen-update --record   (install.sh) remember installed files as unedited
#
# A file you never edited is replaced with the new one. A file you DID edit is
# left exactly as it is, and the new version is written next to it as
# <file>.new for you to merge by hand. Nothing is ever deleted.
set -uo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
SRC="$REPO/config"
DEST="$HOME/.config"
STATE="$DEST/protogreen"
MANIFEST="$STATE/installed.sha256"   # hash of every file as install/update wrote it
PLACEHOLDER="__HOME__"
BRANCH=main

g(){ printf '\033[1;32m%s\033[0m\n' "$*"; }
y(){ printf '\033[33m%s\033[0m\n' "$*"; }
r(){ printf '\033[31m%s\033[0m\n' "$*"; }
ask(){ read -rp "$1 [y/N] " a; [[ "$a" =~ ^[Yy]$ ]]; }

repo_files(){ (cd "$SRC" && find . -type f -printf '%P\n' | sort); }

# Carry the GPU PROFILE and MONITOR blocks install.sh wrote for this machine from
# $1 (installed hyprland.conf) into $2 (new one), so an update keeps your hardware.
keep_blocks() {
  local cur="$1" new="$2" m
  for m in "GPU PROFILE" "MONITOR"; do
    grep -q ">>> PROTOGREEN $m >>>" "$cur" && grep -q ">>> PROTOGREEN $m >>>" "$new" || continue
    awk -v m="$m" -v curf="$cur" '
      BEGIN { while ((getline l < curf) > 0) {
                if (l ~ "<<< PROTOGREEN " m " <<<") inb=0
                if (inb) body = body l "\n"
                if (l ~ ">>> PROTOGREEN " m " >>>") inb=1 } }
      $0 ~ ">>> PROTOGREEN " m " >>>" { print; printf "%s", body; skip=1; next }
      $0 ~ "<<< PROTOGREEN " m " <<<" { skip=0 }
      !skip' "$new" > "$new.tmp" && mv "$new.tmp" "$new"
  done
}

# What config/<rel> looks like once installed on this machine.
render() {
  local rel="$1" out="$2"
  cp -p "$SRC/$rel" "$out"
  grep -qI "$PLACEHOLDER" "$out" && sed -i "s|$PLACEHOLDER|$HOME|g" "$out"
  [ "$rel" = hypr/hyprland.conf ] && [ -f "$DEST/$rel" ] && keep_blocks "$DEST/$rel" "$out"
  return 0
}

record() {
  mkdir -p "$STATE"
  repo_files | while IFS= read -r rel; do
    [ -f "$DEST/$rel" ] && printf '%s  %s\n' "$(sha256sum < "$DEST/$rel" | cut -d' ' -f1)" "$rel"
  done > "$MANIFEST"
  printf '%s\n' "$REPO" > "$STATE/repo"
}

sync_configs() {
  local from="$1" rel dst new nh ch added=0 updated=0 kept=()
  declare -A known
  if [ -r "$MANIFEST" ]; then
    while read -r h rel; do known["$rel"]="$h"; done < "$MANIFEST"
  else
    y "  no install record found (installed before 1.1.0) - every file that differs"
    y "  from the new version is treated as edited and gets a .new next to it"
  fi
  mkdir -p "$STATE"
  local tmp; tmp="$(mktemp -d "$STATE/.update.XXXXXX")"

  while IFS= read -r rel; do
    dst="$DEST/$rel"; new="$tmp/file"
    render "$rel" "$new"
    nh="$(sha256sum < "$new" | cut -d' ' -f1)"
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")"; mv "$new" "$dst"; added=$((added + 1))
    else
      ch="$(sha256sum < "$dst" | cut -d' ' -f1)"
      if [ "$ch" = "$nh" ]; then
        :                                            # already current
      elif [ "$ch" = "${known[$rel]:-}" ]; then
        mv "$new" "$dst"; updated=$((updated + 1))   # untouched since install
      else
        mv "$new" "$dst.new"; kept+=("$rel")         # yours - leave it alone
        continue
      fi
    fi
    known["$rel"]="$nh"
  done < <(repo_files)
  rm -rf "$tmp"

  for rel in "${!known[@]}"; do printf '%s  %s\n' "${known[$rel]}" "$rel"; done \
    | sort -k2 > "$MANIFEST"
  printf '%s\n' "$REPO" > "$STATE/repo"

  echo
  g "updated $from -> $(cat "$REPO/VERSION")"
  echo "  $updated file(s) updated, $added new"
  if [ "${#kept[@]}" -gt 0 ]; then
    y "  ${#kept[@]} file(s) you edited were NOT touched. The new version is next to each:"
    for rel in "${kept[@]}"; do echo "    ~/.config/$rel.new"; done
    y "  compare with: diff ~/.config/<file> ~/.config/<file>.new"
  fi
  echo "  log out and back in (or: hyprctl reload) to load the changes"
}

main() {
  case "${1:-}" in
    --record) record; exit 0 ;;
    --sync)   sync_configs "${2:-?}"; exit 0 ;;
  esac

  command -v git >/dev/null || { r "git is not installed"; exit 1; }
  [ -d "$REPO/.git" ] || { r "$REPO is not a git clone. Re-clone it:"
                           r "  git clone https://github.com/WafflingNinja/protogreen.git"; exit 1; }
  cd "$REPO" || exit 1

  local cur new
  cur="$(cat VERSION 2>/dev/null || echo 0.0.0)"
  g "== PROTO//GREEN update =="
  echo "installed: $cur"
  git fetch -q origin "$BRANCH" || { r "could not reach GitHub"; exit 1; }
  new="$(git show "origin/$BRANCH:VERSION" 2>/dev/null || echo "$cur")"
  echo "latest:    $new"

  if git merge-base --is-ancestor "origin/$BRANCH" HEAD; then
    g "already up to date"; exit 0
  fi

  echo; echo "what changed:"
  git log --oneline --no-decorate "HEAD..origin/$BRANCH" | sed 's/^/  /'
  echo
  ask "update to $new?" || { y "nothing changed"; exit 0; }

  git merge -q --ff-only "origin/$BRANCH" || {
    r "could not fast-forward $REPO - it has local commits or edits."
    r "your ~/.config was not touched. Clean up the clone (git status) and retry."
    exit 1
  }
  # hand over to the NEW update.sh, so a fix to the sync logic applies to this update
  exec bash "$REPO/update.sh" --sync "$cur"
}

main "$@"
