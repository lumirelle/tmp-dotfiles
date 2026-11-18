# Jump into a git worktree.
#
# Shows each worktree's repo / branch / path in fzf and cd's into the pick.
# Inside a git repository it offers that repository's worktrees; anywhere else
# it offers every worktree under <root>/.worktrees.
#
# Worktrees live under <root>/.worktrees, the layout tuios uses when
# [worktree] path is set in its config.toml.
#
#   wt                        # pick a worktree and cd into it
#   wt ls                     # every worktree as a repo / branch / path table
#   wt --root D:/work/repos   # another root; worktrees live in DIR/.worktrees
#   $env.GIT_BARE_ROOT = '~/src'   # set a different default root
export def --env wt [
  subcommand?: string  # `ls` lists every worktree instead of picking one
  --root (-r): path    # root directory; default is $env.GIT_BARE_ROOT or ~/git
] {
  let sub = ($subcommand | default "")
  if $sub not-in ["" "ls"] {
    error make { msg: $"wt: unknown subcommand: ($sub); see 'wt --help'" }
  }

  let root = (
    $root
    | default ($env.GIT_BARE_ROOT? | default ($nu.home-dir | path join "git"))
  )
  let wt_root = ($root | path join ".worktrees")
  # glob wants forward slashes, even where path join wrote backslashes
  let wt_glob_root = ($wt_root | str replace --all '\' '/')

  # Only when inside a repository does the interactive pick narrow to it, so
  # skip the git call for `ls`.
  let in_repo = (
    $sub != "ls" and ((^git rev-parse --git-dir | complete) | get exit_code) == 0
  )

  # Every worktree under <root>/.worktrees, found by the .git file each one
  # carries. The repo name is the first folder under the worktrees dir.
  let all_worktrees = {||
    if not ($wt_root | path exists) {
      error make { msg: $"wt: no such directory: ($wt_root)" }
    }
    glob $"($wt_glob_root)/**/.git"
    | where {|p| ($p | path type) == "file" }
    | each {|p| $p | path dirname }
    | uniq
    | each {|dir|
        let r = (^git -C $dir rev-parse --abbrev-ref HEAD | complete)
        if $r.exit_code != 0 {
          null
        } else {
          let head = ($r.stdout | str trim)
          let rel = ($dir | path relative-to $wt_root)
          {
            repo: ($rel | path split | first | str replace --regex '\.git$' '')
            branch: (if ($head == "HEAD") { "detached" } else { $head })
            path: $dir
          }
        }
      }
    | where {|r| $r != null }
  }

  # The worktrees git reports for the repository the shell is in.
  let repo_worktrees = {||
    let blocks = (
      ^git worktree list --porcelain
      | lines
      | split list ""
      | where {|b| ($b | length) > 0 }
    )
    let repo = (
      $blocks
      | get 0
      | get 0
      | str replace --regex '^worktree ' ''
      | path basename
      | str replace --regex '\.git$' ''
    )
    $blocks
    | each {|b|
        # skip the bare checkout itself, and worktrees whose directory is gone
        if ($b | any {|l| $l == "bare" or $l == "prunable" }) {
          null
        } else {
          let path = ($b | get 0 | str replace --regex '^worktree ' '')
          let branch = (
            $b
            | where {|l| $l | str starts-with "branch " }
            | get 0?
            | default "detached"
            | str replace --regex '^branch refs/heads/' ''
          )
          { repo: $repo, branch: $branch, path: $path }
        }
      }
    | where {|r| $r != null }
  }

  let rows = (
    (if $in_repo { do $repo_worktrees } else { do $all_worktrees })
    | sort-by repo branch path
  )

  if ($rows | is-empty) {
    let place = (if $in_repo { "this repository" } else { $wt_root })
    print --stderr $"wt: no worktrees under ($place)"
    return
  }

  # a table: repo / branch / path, so it pipes like any other nushell data
  if $sub == "ls" {
    return $rows
  }

  let result = (
    $rows
    | each {|r| $"($r.repo)  ($r.branch)  ($r.path)\t($r.path)" }
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
