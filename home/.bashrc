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
  local root=${1:-${GIT_BARE_ROOT:-$HOME/git}}
  local repo line path branch skip repo_name short
  local -a rows=()

  [[ -d $root ]] || { printf 'wt: no such directory: %s\n' "$root" >&2; return 1; }

  for repo in "$root"/*.git; do
    [[ -d $repo ]] || continue
    repo_name=${repo##*/}; repo_name=${repo_name%.git}
    path='' branch=detached skip=0
    while IFS= read -r line || [[ -n $line ]]; do
      case $line in
        '')
          if (( ! skip )) && [[ -n $path ]]; then
            short=${path/#*\/tuios\/worktrees\//tuios/worktrees/}
            rows+=("$repo_name  $branch  $short"$'\t'"$path")
          fi
          path='' branch=detached skip=0 ;;
        'worktree '*)  path=${line#worktree } ;;
        'branch '*)    branch=${line#branch refs/heads/} ;;
        bare|prunable) skip=1 ;;
      esac
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; printf '\n')
  done

  if (( ${#rows[@]} == 0 )); then
    printf 'wt: no worktrees under %s\n' "$root" >&2
    return 0
  fi

  local picked
  picked=$(printf '%s\n' "${rows[@]}" | /usr/bin/sort | fzf --delimiter $'\t' --with-nth 1 --reverse --height 40% --prompt 'worktree> ') || return 0
  [[ -n $picked ]] || return 0
  cd -- "${picked##*$'\t'}"
}
alias lzg='lazygit'
## tuios
function tuios {
  if [[ ${1:-} == wt ]]; then command tuios worktree "${@:2}"; else command tuios "$@"; fi
}
alias tos='tuios'
