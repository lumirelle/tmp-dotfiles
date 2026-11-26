# Jump into a git worktree.
#
# Shows each worktree's repo / branch / path in fzf and cd's into the pick.
# Inside a git repository it offers that repository's worktrees; anywhere else
# it offers every worktree under <root>/.worktrees.
#
# Worktrees live under <root>/.worktrees/{repo}/{branch}, the layout tuios uses
# when [worktree] path is set in its config.toml. `wt add` creates one in the
# same shape, from the current repository unless --repo says otherwise; a
# branch that does not exist yet is created from HEAD.
#
#   wt                             # pick a worktree and cd into it
#   wt ls                          # every worktree as a repo / branch / path table
#   wt add feat/retry              # create <root>/.worktrees/<repo>/feat/retry, cd into it
#   wt add fix --repo D:/src/api   # a worktree of another repository
#   wt --root D:/work/repos        # another root; worktrees live in DIR/.worktrees
#   $env.GIT_BARE_ROOT = '~/src'   # set a different default root
export def --env wt [
  subcommand?: string  # `ls` lists every worktree; `add <branch>` creates one
  branch?: string      # branch name for `add`
  --root (-r): path    # root directory; default is $env.GIT_BARE_ROOT or ~/git
  --repo: path         # repository for `add`; default is the current one
] {
  let sub = ($subcommand | default "")
  if $sub not-in ["" "ls" "add"] {
    error make { msg: $"wt: unknown subcommand: ($sub); see 'wt --help'" }
  }
  let branch_name = ($branch | default "")
  if ($sub == "add") and (($branch_name | str length) == 0) {
    error make { msg: "wt add: needs a branch name; see 'wt --help'" }
  }
  if ($sub != "add") and (($branch_name | str length) > 0) {
    error make { msg: $"wt: unexpected argument: ($branch_name); see 'wt --help'" }
  }

  let root = (
    $root
    | default ($env.GIT_BARE_ROOT? | default ($nu.home-dir | path join "git"))
  )
  let wt_root = ($root | path join ".worktrees")

  # wt add: <root>/.worktrees/{repo}/{branch}, then cd into it
  if $sub == "add" {
    let gdir = ($repo | default ".")
    let common = (^git -C $gdir rev-parse --path-format=absolute --git-common-dir | complete)
    if $common.exit_code != 0 {
      error make { msg: $"wt add: not a git repository: ($gdir)" }
    }
    let common_path = ($common.stdout | str trim)
    let folder = (
      if (($common_path | path basename) == ".git") {
        $common_path | path dirname | path basename
      } else {
        $common_path | path basename
      }
    )
    let dest = ($wt_root | path join $folder | path join $branch_name)
    if ($dest | path exists) {
      error make { msg: $"wt add: already exists: ($dest)" }
    }
    let local = (^git -C $gdir rev-parse --verify --quiet $"refs/heads/($branch_name)" | complete)
    if $local.exit_code == 0 {
      ^git -C $gdir worktree add $dest $branch_name
    } else {
      ^git -C $gdir worktree add -b $branch_name $dest
    }
    cd $dest
    return
  }

  # Only when inside a repository does the interactive pick narrow to it, so
  # skip the git call for `ls`.
  let in_repo = (
    $sub != "ls" and ((^git rev-parse --git-dir | complete) | get exit_code) == 0
  )

  # Every worktree under <root>/.worktrees: walk down until a directory holds a
  # .git, then stop. Stopping at the .git keeps node_modules out of the walk and
  # keeps a worktree's submodules from being listed as worktrees of their own.
  # The repo name is the first folder under the worktrees dir, and the branch is
  # read straight from the worktree's HEAD file - no git subprocess per entry.
  let all_worktrees = {||
    if not ($wt_root | path exists) {
      error make { msg: $"wt: no such directory: ($wt_root)" }
    }
    let dirs = (do {
      mut queue = [$wt_root]
      mut out = []
      while ($queue | is-not-empty) {
        let dir = ($queue | first)
        $queue = ($queue | skip 1)
        if (($dir | path join ".git") | path exists) {
          $out = ($out | append $dir)
        } else {
          $queue = ($queue | append (ls -a $dir | where type == dir | get name))
        }
      }
      $out
    })
    $dirs
    | par-each {|dir|
        try {
          let gd = (open ($dir | path join ".git") | str trim | str replace --regex '^gitdir: ' '')
          let head = (open (($dir | path join $gd) | path join "HEAD") | str trim)
          let rel = ($dir | path relative-to $wt_root)
          {
            repo: ($rel | path split | first | str replace --regex '\.git$' '')
            branch: (if ($head | str starts-with "ref: refs/heads/") { $head | str replace 'ref: refs/heads/' '' } else { "detached" })
            path: $dir
          }
        } catch { null }
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
