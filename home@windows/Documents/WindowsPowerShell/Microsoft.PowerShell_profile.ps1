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
  $help = $false
  for ($i = 0; $i -lt $args.Count; $i++) {
    switch -Regex ([string]$args[$i]) {
      '^(-h|--help)$' { $help = $true }
      '^ls$' { $sub = 'ls' }
      '^(-r|--root)$' {
        if ($i + 1 -ge $args.Count) { Write-Error "wt: $($args[$i]) needs a directory"; return }
        $i++
        $root = [string]$args[$i]
      }
      default {
        Write-Error "wt: unknown argument: $($args[$i]); run 'wt --help' for usage."
        return
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

usage: wt [subcommand] [--root DIR]

  wt                pick a worktree and cd into it
  ls                list every worktree under DIR/.worktrees, without picking
  -r, --root DIR    root directory (default: $env:GIT_BARE_ROOT or ~/git)
  -h, --help        show this help
'@ | Out-Host
    return
  }

  $rootDir = if ($root) { $root } elseif ($env:GIT_BARE_ROOT) { $env:GIT_BARE_ROOT } else { Join-Path $HOME 'git' }
  $wtRoot = Join-Path $rootDir '.worktrees'

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
    foreach ($gitFile in Get-ChildItem -LiteralPath $wtRoot -Recurse -Force -File -Filter '.git' -ErrorAction SilentlyContinue) {
      $dir = $gitFile.DirectoryName
      $branch = (& git -C $dir rev-parse --abbrev-ref HEAD 2>$null)
      if ($LASTEXITCODE -ne 0) { continue }
      if ($branch -eq 'HEAD') { $branch = 'detached' }
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
