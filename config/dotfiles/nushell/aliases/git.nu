# Jump into a git worktree.
#
# Collects every worktree of the bare *.git repositories under ~/git (by
# default the ones tuios creates in %LOCALAPPDATA%\tuios\worktrees), shows
# repo / branch / path in fzf, and cd's into the pick.
#
#   wt                 # all repos under ~/git
#   wt D:/work/repos   # another root
#   $env.GIT_BARE_ROOT = '~/src'   # set a different default root
export def --env wt [
  root?: path  # directory holding the *.git bare repos; default ~/git
] {
  let root = (
    $root
    | default ($env.GIT_BARE_ROOT? | default ($nu.home-dir | path join "git"))
  )

  if not ($root | path exists) {
    error make { msg: $"wt: no such directory: ($root)" }
  }

  let rows = (
    ls $root
    | where {|e| $e.type == "dir" and ($e.name | str ends-with ".git") }
    | each {|repo|
        git -C $repo.name worktree list --porcelain
        | lines
        | split list ""
        | where {|b| ($b | length) > 0 }
        | each {|b|
            # skip the bare checkout itself, and worktrees whose directory is gone
            let skip = ($b | any {|l| $l == "bare" or $l == "prunable" })
            if $skip { null } else {
              let path = ($b | get 0 | str replace --regex '^worktree ' '')
              let branch = (
                $b
                | where {|l| $l | str starts-with "branch " }
                | get 0?
                | default "detached"
                | str replace --regex '^branch refs/heads/' ''
              )
              let repo_name = ($repo.name | path basename | str replace --regex '\.git$' '')
              let short = ($path | str replace --regex '^.*/tuios/worktrees/' 'tuios/worktrees/')
              {
                repo: $repo_name
                branch: $branch
                path: $path
                display: $"($repo_name)  ($branch)  ($short)"
              }
            }
          }
      }
    | flatten
    | where {|r| $r != null }
    | sort-by repo branch
  )

  if ($rows | is-empty) {
    print --stderr $"wt: no worktrees under ($root)"
    return
  }

  let result = (
    $rows
    | each {|r| $"($r.display)\t($r.path)" }
    | str join (char nl)
    | ^fzf --delimiter (char tab) --with-nth 1 --reverse --height 40% --prompt 'worktree> '
    | complete
  )

  # fzf exits 130 when it is dismissed; keep the shell where it is
  if $result.exit_code != 0 { return }

  let picked = ($result.stdout | str trim)
  if ($picked | is-empty) { return }

  cd ($picked | split row (char tab) | last)
}

export alias lzg = lazygit
