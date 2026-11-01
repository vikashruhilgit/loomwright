#!/usr/bin/env bash
# git-integrity-lib.sh — SOURCED library (never executed, and never named
# `provider-*.sh`: setup-providers.sh globs that pattern and lens-run.sh would
# accept such a file as a provider). The ONE home of git_integrity_fingerprint,
# the security-relevant `.git` state snapshot that is taken before a provider CLI
# runs and compared after it. Callers: lens-run.sh (refs scope `all`) and
# write-run.sh (refs scope `own`), both beside this file.
#
# API
#   git_integrity_fingerprint <repo> [all|own]
#     Prints a text fingerprint of <repo>'s git state to stdout. Two runs over
#     unchanged state print identical text, so a caller compares a "before" and an
#     "after" snapshot byte for byte. The text is made of sections, each opened by
#     a header line ending in `:` (`remotes:`, `local-config:`, `config-cksum:`,
#     `refs:`, `head:`, `hooks:`, plus `own`'s extra sections below). Under a
#     header, the FIRST field of each line identifies the thing it describes (a
#     remote, a config key, a file path, a ref name — `refs:` lines are
#     `<sha> <ref>`, so there it is the second field), so a caller can name what
#     changed without parsing anything else. Config VALUES are printed only in the
#     `local-config:` section (as `key=value`, the shape `git config --list`
#     prints, included files followed); a caller naming a change must print the
#     key, never the value.
#
#     <repo> is any work tree: a plain clone, or a linked worktree whose `.git` is
#     a FILE. Paths are resolved through `git rev-parse --absolute-git-dir` and
#     `--git-common-dir`, never by appending `/.git` to <repo>.
#
#     Refs scope:
#       all  (the default) — every ref (`git show-ref`), HEAD, the remotes, the
#            local config and its file checksum, and the non-sample hooks of the
#            git dir (and of the common dir when that differs). lens-run.sh's
#            throwaway sandbox uses it: nothing else writes there, so any ref
#            change is the provider's.
#       own  — HEAD, the symbolic ref HEAD points at and that branch ref only,
#            plus everything `all` reads other than the other refs, plus:
#              worktree-config-cksum:  the linked worktree's own config.worktree
#              info-exclude-cksum:     the common dir's info/exclude (an entry
#                                      there hides a file from `git status` and
#                                      from `git clean`)
#              info-attributes-cksum:  the common dir's info/attributes (it can
#                                      bind a path to a filter driver)
#              git-dirs:               where git resolves the git dir and the
#                                      common dir (`gitdir <path>`,
#                                      `commondir <path>`), the checkout's `.git`
#                                      (a dir, or the gitfile's checksum) and the
#                                      git dir's `commondir` file: a rewritten
#                                      gitfile or commondir redirects every later
#                                      git command to another config
#              hooks-path:             the files of the directory core.hooksPath
#                                      names, when it is set (a relative value is
#                                      resolved from <repo>)
#            write-run.sh uses it in a real worktree that parallel siblings
#            share a repository with: a sibling worker committing on its OWN
#            branch moves a ref this scope never reads, so it is never read as
#            tampering. What `own` therefore does not see: a NEW branch or tag
#            the provider creates (it can change no code that runs, and the
#            caller's HEAD and branch are pinned).
#     An unrecognised scope reads as `all` (the broader read).
#
#   Every git call here only READS (config, remote, show-ref, rev-parse,
#   symbolic-ref): none refreshes the index, so a planted core.fsmonitor or hook
#   is never executed by taking a fingerprint.
#
# Bash 3.2 compatible. Prints nothing to stderr.

# _gil_abs_dir <repo> <rev-parse-flag> — the absolute, physical path git reports
# for <flag> (`--absolute-git-dir` / `--git-common-dir`), or empty.
_gil_abs_dir() {
  local repo="$1" flag="$2" d
  d="$(git -C "$repo" rev-parse "$flag" 2>/dev/null)"
  [ -n "$d" ] || return 0
  case "$d" in
    /*) ;;
    *) d="$repo/$d" ;;
  esac
  ( cd "$d" 2>/dev/null && pwd -P )
}

# _gil_cksum_file <file> — `<file> <cksum>` when it exists, else
# `<file> absent`. A symlink is reported as a link, never followed.
_gil_cksum_file() {
  local f="$1"
  if [ -L "$f" ]; then
    printf '%s link=%s\n' "$f" "$(readlink "$f" 2>/dev/null)"
  elif [ -f "$f" ]; then
    printf '%s %s\n' "$f" "$(cksum < "$f" 2>/dev/null)"
  else
    printf '%s absent\n' "$f"
  fi
}

# _gil_list_hooks <dir> — one `<path> x=<0|1> <cksum>` line per non-sample
# regular file or symlink under <dir>, sorted.
_gil_list_hooks() {
  local dir="$1" hookf hx
  if [ -L "$dir" ]; then
    printf '%s link=%s\n' "$dir" "$(readlink "$dir" 2>/dev/null)"
    return 0
  fi
  [ -d "$dir" ] || return 0
  find "$dir" \( -type f -o -type l \) ! -name '*.sample' -print 2>/dev/null \
    | env LC_ALL=C sort \
    | while IFS= read -r hookf; do
        if [ -x "$hookf" ]; then hx=1; else hx=0; fi
        printf '%s x=%s %s\n' "$hookf" "$hx" "$(cksum < "$hookf" 2>/dev/null)"
      done
}

git_integrity_fingerprint() {
  local repo="$1" scope="${2:-all}" gitdir commondir ownref hp
  case "$scope" in
    own) ;;
    *) scope="all" ;;
  esac
  gitdir="$(_gil_abs_dir "$repo" --absolute-git-dir)"
  commondir="$(_gil_abs_dir "$repo" --git-common-dir)"
  [ -n "$commondir" ] || commondir="$gitdir"
  {
    printf 'remotes:\n'
    git -C "$repo" remote -v 2>/dev/null | env LC_ALL=C sort
    printf 'local-config:\n'
    git -C "$repo" config --local --includes --list 2>/dev/null | env LC_ALL=C sort
    printf 'config-cksum:\n'
    [ -n "$commondir" ] && _gil_cksum_file "$commondir/config"
    printf 'refs:\n'
    if [ "$scope" = "all" ]; then
      git -C "$repo" show-ref 2>/dev/null | env LC_ALL=C sort
    else
      ownref="$(git -C "$repo" symbolic-ref -q HEAD 2>/dev/null)"
      if [ -n "$ownref" ]; then
        printf 'symref HEAD->%s\n' "$ownref"
        git -C "$repo" show-ref --verify "$ownref" 2>/dev/null
      else
        printf 'symref HEAD->(detached)\n'
      fi
    fi
    printf 'head:\n'
    git -C "$repo" rev-parse HEAD 2>/dev/null
    printf 'hooks:\n'
    [ -n "$gitdir" ] && _gil_list_hooks "$gitdir/hooks"
    if [ -n "$commondir" ] && [ "$commondir" != "$gitdir" ]; then
      _gil_list_hooks "$commondir/hooks"
    fi
    if [ "$scope" = "own" ]; then
      printf 'worktree-config-cksum:\n'
      [ -n "$gitdir" ] && _gil_cksum_file "$gitdir/config.worktree"
      printf 'info-exclude-cksum:\n'
      [ -n "$commondir" ] && _gil_cksum_file "$commondir/info/exclude"
      printf 'info-attributes-cksum:\n'
      [ -n "$commondir" ] && _gil_cksum_file "$commondir/info/attributes"
      printf 'git-dirs:\n'
      printf 'gitdir %s\n' "$gitdir"
      printf 'commondir %s\n' "$commondir"
      if [ -d "$repo/.git" ] && [ ! -L "$repo/.git" ]; then
        printf '%s dir\n' "$repo/.git"
      else
        _gil_cksum_file "$repo/.git"
      fi
      [ -n "$gitdir" ] && _gil_cksum_file "$gitdir/commondir"
      printf 'hooks-path:\n'
      hp="$(git -C "$repo" config --get core.hooksPath 2>/dev/null)"
      if [ -n "$hp" ]; then
        case "$hp" in
          /*) ;;
          "~"/*) hp="${HOME:-}/${hp#"~"/}" ;;
          *) hp="$repo/$hp" ;;
        esac
        printf 'core.hooksPath %s\n' "$hp"
        _gil_list_hooks "$hp"
      fi
    fi
  }
}
