# -- ENCODING --
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [Text.Encoding]::UTF8

# -- ENVIRONMENT --
$env:EDITOR = "nvim"
$env:VISUAL = "nvim"
if (Test-Path "$env:USERPROFILE\bin") {
  $env:PATH = "$env:USERPROFILE\bin;$env:PATH"
}
if (Test-Path "$env:USERPROFILE\.local\bin") {
  $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
}
## Mise, https://mise.jdx.dev/
(&mise activate pwsh) | Out-String | Invoke-Expression
## Starship, https://starship.rs/
(&starship init powershell) | Invoke-Expression
## Zoxide, https://github.com/ajeetdsouza/zoxide
(&zoxide init powershell) | Out-String | Invoke-Expression
## Fnox, https://fnox.jdx.dev/
(&fnox activate powershell) | Out-String | Invoke-Expression

# -- ALIASES --
## built-in
New-Alias -Name which -Value where.exe
New-Alias -Name touch -Value New-Item
function readtime {
  param([string]$FilePath)
  if (-not $FilePath) { Write-Error 'usage: readtime <file>'; return }
  if (-not (Test-Path -LiteralPath $FilePath)) { Write-Error "readtime: no such file: $FilePath"; return }
  $wpm = if ($env:READTIME_WPM) { [int]$env:READTIME_WPM } else { 200 }
  $content = Get-Content -LiteralPath $FilePath -Raw
  $words = if ($content) { ($content | Measure-Object -Word).Words } else { 0 }
  '≈ {0} min <WPM: {1}>' -f [math]::Floor($words / $wpm + 0.5), $wpm
}
## cwd-file-exts
function rank-exts {
  $counts = @{}
  Get-ChildItem -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git)[\\/]' } |
    ForEach-Object {
      $dot = $_.Name.LastIndexOf('.')
      $ext = if ($dot -gt 0) { $_.Name.Substring($dot) } else { $_.Name }
      if ($counts.ContainsKey($ext)) { $counts[$ext]++ } else { $counts[$ext] = 1 }
    }
  $counts.GetEnumerator() |
    Sort-Object Value -Descending |
    ForEach-Object { '{0,8}  {1}' -f $_.Value, $_.Key }
}
## fastfetch
New-Alias -Name ff -Value fastfetch
## pm
New-Alias -Name wgt -Value winget
New-Alias -Name pcm -Value pacman
## chezmoi
New-Alias -Name ch -Value chezmoi
## git
function wt {
  $sub = $null
  $root = $null
  $repo = $null
  $branchArg = $null
  $help = $false
  for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ([string]$args[$i]) {
      '^(-h|--help)$' { $help = $true }
      '^ls$' { $sub = 'ls' }
      '^add$' { $sub = 'add' }
      '^(-r|--root)$' {
        if ($i + 1 -ge $args.Count) { Write-Error "wt: $($args[$i]) needs a directory"; return }
        $i++
        $root = [string]$args[$i]
      }
      '^--repo$' {
        if ($i + 1 -ge $args.Count) { Write-Error 'wt: --repo needs a directory'; return }
        $i++
        $repo = [string]$args[$i]
      }
      default {
        if ([string]$args[$i] -like '-*') {
          Write-Error "wt: unknown argument: $($args[$i]); run 'wt --help' for usage."
          return
        }
        if ($branchArg) {
          Write-Error "wt: unexpected argument: $($args[$i]); run 'wt --help' for usage."
          return
        }
        $branchArg = [string]$args[$i]
      }
    }
  }

  if ($help) {
    @'
Jump into a git worktree.

With no subcommand, shows each worktree's repo / branch / path in fzf and
cd's into the pick. Inside a git repository it offers that repository's
worktrees; anywhere else it offers every worktree under DIR/.worktrees.

Worktrees live under DIR/.worktrees, the layout tuios uses when [worktree]
path is set in its config.toml.

usage: wt [subcommand] [args]

  wt                pick a worktree and cd into it
  ls                list every worktree under DIR/.worktrees, without picking
  add <branch>      create DIR/.worktrees/<repo>/<branch> and cd into it.
                    Uses the current repository unless --repo DIR is given;
                    a branch that does not exist yet is created from HEAD.
  -r, --root DIR    root directory (default: $env:GIT_BARE_ROOT or ~/git)
  --repo DIR        repository for add (default: the current one)
  -h, --help        show this help
'@ | Out-Host
    return
  }

  $rootDir = if ($root) { $root } elseif ($env:GIT_BARE_ROOT) { $env:GIT_BARE_ROOT } else { Join-Path $HOME 'git' }
  $wtRoot = Join-Path $rootDir '.worktrees'

  if ($sub -eq 'add') {
    if (-not $branchArg) {
      Write-Error 'wt add: needs a branch name. usage: wt add <branch> [--repo DIR]'
      return
    }
    $gdir = if ($repo) { $repo } else { '.' }
    $common = (& git -C $gdir rev-parse --path-format=absolute --git-common-dir 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $common) { Write-Error "wt add: not a git repository: $gdir"; return }
    $common = @($common)[0].TrimEnd('\', '/')
    $folder = if ((Split-Path -Leaf $common) -eq '.git') {
      Split-Path -Leaf (Split-Path -Parent $common)
    } else {
      Split-Path -Leaf $common
    }
    $dest = Join-Path (Join-Path $wtRoot $folder) $branchArg
    if (Test-Path -LiteralPath $dest) { Write-Error "wt add: already exists: $dest"; return }
    git -C $gdir show-ref --verify --quiet "refs/heads/$branchArg"
    if ($LASTEXITCODE -eq 0) {
      git -C $gdir worktree add $dest $branchArg
    } else {
      git -C $gdir worktree add -b $branchArg $dest
    }
    if ($LASTEXITCODE -ne 0) { return }
    Set-Location -LiteralPath $dest
    return
  }

  if ($branchArg) {
    Write-Error "wt: unexpected argument: $branchArg; run 'wt --help' for usage."
    return
  }

  # Only when inside a repository does the interactive pick narrow to it, so
  # skip the git call for `ls`.
  if ($sub -ne 'ls') {
    git rev-parse --git-dir 2>$null | Out-Null
    $useRepo = ($LASTEXITCODE -eq 0)
  } else {
    $useRepo = $false
  }

  $rows = @()
  if ($useRepo) {
    # inside a repository: every worktree git reports for it
    $repoName = $null
    $path = $null
    $branch = 'detached'
    $skip = $false
    foreach ($line in @(git worktree list --porcelain 2>$null) + '') {
      if ($line -eq '') {
        if (-not $skip -and $path) {
          $rows += [pscustomobject]@{ Repo = $repoName; Branch = $branch; Path = $path; Display = "$repoName  $branch  $path" }
        }
        $path = $null
        $branch = 'detached'
        $skip = $false
      } elseif ($line -like 'worktree *') {
        $path = $line.Substring(9)
        if (-not $repoName) { $repoName = (Split-Path -Leaf $path) -replace '\.git$', '' }
      } elseif ($line -like 'branch refs/heads/*') {
        $branch = $line.Substring(18)
      } elseif ($line -in 'bare', 'prunable') {
        $skip = $true
      }
    }
  } else {
    if (-not (Test-Path -LiteralPath $wtRoot)) { Write-Error "wt: no such directory: $wtRoot"; return }
    # Walk down until a directory holds a .git, then stop: node_modules is never
    # entered and a worktree's submodules are not listed as worktrees.
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($wtRoot)
    $dirs = [System.Collections.Generic.List[string]]::new()
    while ($queue.Count -gt 0) {
      $dir = $queue.Dequeue()
      if (Test-Path -LiteralPath (Join-Path $dir '.git')) {
        $dirs.Add($dir)
      } else {
        foreach ($child in Get-ChildItem -LiteralPath $dir -Force -Directory -ErrorAction SilentlyContinue) {
          $queue.Enqueue($child.FullName)
        }
      }
    }
    foreach ($dir in $dirs) {
      $gitFile = Join-Path $dir '.git'
      if (-not (Test-Path -LiteralPath $gitFile -PathType Leaf)) { continue }
      $gd = (Get-Content -LiteralPath $gitFile -Raw -ErrorAction SilentlyContinue)
      if (-not $gd) { continue }
      $gd = ($gd.Trim() -replace '^gitdir: ', '')
      if (-not [System.IO.Path]::IsPathRooted($gd)) { $gd = Join-Path $dir $gd }
      $head = Get-Content -LiteralPath (Join-Path $gd 'HEAD') -Raw -ErrorAction SilentlyContinue
      if ($null -eq $head) { continue }
      $head = $head.Trim()
      $branch = if ($head.StartsWith('ref: refs/heads/')) { $head.Substring(16) } else { 'detached' }
      $rel = $dir.Substring($wtRoot.Length).TrimStart('\', '/')
      $repoName = (($rel -split '[\\/]')[0]) -replace '\.git$', ''
      $rows += [pscustomobject]@{ Repo = $repoName; Branch = $branch; Path = $dir; Display = "$repoName  $branch  $dir" }
    }
  }

  if ($rows.Count -eq 0) {
    $place = if ($useRepo) { 'this repository' } else { $wtRoot }
    Write-Error "wt: no worktrees under $place"
    return
  }

  $rows = $rows | Sort-Object Repo, Branch, Path

  if ($sub -eq 'ls') {
    $rows | ForEach-Object { '{0}  {1}  {2}' -f $_.Repo, $_.Branch, $_.Path }
    return
  }

  $picked = $rows | ForEach-Object { "$($_.Display)`t$($_.Path)" } | fzf --delimiter '\t' --with-nth 1 --reverse --height 40% --prompt 'worktree> '
  if (-not $picked) { return }
  Set-Location -LiteralPath ($picked -split "`t")[-1]
}
New-Alias -Name lzg -Value lazygit
## tuios
function tuios {
  if ($args.Count -gt 0 -and $args[0] -eq 'wt') {
    tuios.exe worktree @($args | Select-Object -Skip 1)
  } else {
    tuios.exe @args
  }
}
Set-Alias -Name tos -Value tuios
## ai
New-Alias -Name cc -Value claude
