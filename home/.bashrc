# -- ENVIRONMENT SETUP --
export EDITOR='nvim'
export VISUAL='nvim'
if [ -d "$HOME/bin" ]; then
  PATH="$HOME/bin:$PATH"
fi
if [ -d "$HOME/.local/bin" ]; then
  PATH="$HOME/.local/bin:$PATH"
fi
if [ -d "$USERPROFILE/bin" ]; then
  PATH="$USERPROFILE/bin:$PATH"
fi
if [ -d "$USERPROFILE/.local/bin" ]; then
  PATH="$USERPROFILE/.local/bin:$PATH"
fi
## Mise, https://mise.jdx.dev/
eval "$(mise activate bash)"
## Starship, https://starship.rs/
eval "$(starship init bash)"
## Zoxide, https://github.com/ajeetdsouza/zoxide
eval "$(zoxide init bash)"
## Fnox, https://fnox.jdx.dev/
eval "$(fnox activate bash)"

# -- ALIASES --
## built-in
alias ll='ls -l'
alias la='ls --all'
alias cls='clear'
function readtime {
  local file=${1:?usage: readtime <file>}
  local wpm=${READTIME_WPM:-200} words
  [[ -f $file ]] || { printf 'readtime: no such file: %s\n' "$file" >&2; return 1; }
  words=$(wc -w <"$file")
  printf '≈ %d min <WPM: %s>\n' $(( (words + wpm / 2) / wpm )) "$wpm"
}
## cwd-file-exts
function rank-exts {
  local -A count=()
  local f base ext
  while IFS= read -r -d '' f; do
    base=${f##*/}
    if [[ $base == ?*.* ]]; then ext=.${base##*.}; else ext=$base; fi
    count[$ext]=$(( ${count[$ext]:-0} + 1 ))
  done < <(/usr/bin/find -L . -type d \( -name node_modules -o -name .git \) -prune -o -type f -print0 2>/dev/null)
  (( ${#count[@]} )) || return 0
  for ext in "${!count[@]}"; do
    printf '%8d  %s\n' "${count[$ext]}" "$ext"
  done | /usr/bin/sort -rnk1
}
## fastfetch
alias ff='fastfetch'
## pm 
alias wgt='winget'
alias pcm='pacman'
## git
function wt {
  local sub='' root='' help=0
  while (( $# )); do
    case $1 in
      -h|--help) help=1; shift ;;
      ls) sub=ls; shift ;;
      -r|--root)
        if [[ -z ${2:-} ]]; then printf 'wt: %s needs a directory\n' "$1" >&2; return 2; fi
        root=$2; shift 2 ;;
      *)
        printf 'wt: unknown argument: %s\nrun "wt --help" for usage.\n' "$1" >&2
        return 2 ;;
    esac
  done

  if (( help )); then
    cat <<'EOF'
Jump into a git worktree.

With no subcommand, shows each worktree's repo / branch / path in fzf and
cd's into the pick. Inside a git repository it offers that repository's
worktrees; anywhere else it offers every worktree under DIR/.worktrees.

Worktrees live under DIR/.worktrees, the layout tuios uses when [worktree]
path is set in its config.toml.

usage: wt [subcommand] [--root DIR]

  wt                pick a worktree and cd into it
  ls                list every worktree under DIR/.worktrees, without picking
  -r, --root DIR    root directory (default: $GIT_BARE_ROOT or ~/git)
  -h, --help        show this help
EOF
    return 0
  fi

  local root_dir=${root:-${GIT_BARE_ROOT:-$HOME/git}}
  local wt_root=$root_dir/.worktrees
  local -a rows=()
  local use_repo=0
  local line path branch skip repo_name d rel display place sorted picked
  local disp r b p

  if [[ $sub != ls ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    use_repo=1
  fi

  if (( use_repo )); then
    # inside a repository: every worktree git reports for it
    repo_name='' path='' branch=detached skip=0
    while IFS= read -r line || [[ -n $line ]]; do
      case $line in
        '')
          if (( ! skip )) && [[ -n $path ]]; then
            rows+=("$repo_name  $branch  $path"$'\t'"$repo_name"$'\t'"$branch"$'\t'"$path")
          fi
          path='' branch=detached skip=0 ;;
        'worktree '*)
          path=${line#worktree }
          if [[ -z $repo_name ]]; then repo_name=${path##*/}; repo_name=${repo_name%.git}; fi ;;
        'branch '*)    branch=${line#branch refs/heads/} ;;
        bare|prunable) skip=1 ;;
      esac
    done < <(git worktree list --porcelain 2>/dev/null; printf '\n')
  else
    [[ -d $wt_root ]] || { printf 'wt: no such directory: %s\n' "$wt_root" >&2; return 1; }
    while IFS= read -r d; do
      d=${d%/.git}
      branch=$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null) || continue
      [[ -n $branch ]] || continue
      [[ $branch == HEAD ]] && branch=detached
      rel=${d#"$wt_root"/}
      repo_name=${rel%%/*}
      repo_name=${repo_name%.git}
      rows+=("$repo_name  $branch  $d"$'\t'"$repo_name"$'\t'"$branch"$'\t'"$d")
    done < <(/usr/bin/find "$wt_root" -name .git -type f 2>/dev/null)
  fi

  if (( ${#rows[@]} == 0 )); then
    place=$wt_root
    (( use_repo )) && place='this repository'
    printf 'wt: no worktrees under %s\n' "$place" >&2
    return 0
  fi

  sorted=$(printf '%s\n' "${rows[@]}" | /usr/bin/sort)

  if [[ $sub == ls ]]; then
    while IFS=$'\t' read -r display r b p; do
      printf '%s  %s  %s\n' "$r" "$b" "$p"
    done <<< "$sorted"
    return 0
  fi

  picked=$(printf '%s\n' "$sorted" | fzf --delimiter $'\t' --with-nth 1 --reverse --height 40% --prompt 'worktree> ') || return 0
  [[ -n $picked ]] || return 0
  cd -- "${picked##*$'\t'}"
}
alias lzg='lazygit'
## tuios
function tuios {
  if [[ ${1:-} == wt ]]; then command tuios worktree "${@:2}"; else command tuios "$@"; fi
}
alias tos='tuios'
## ai
alias cc='claude'
