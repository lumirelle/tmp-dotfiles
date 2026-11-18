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
  param([string]$Root)
  if (-not $Root) {
    $Root = if ($env:GIT_BARE_ROOT) { $env:GIT_BARE_ROOT } else { Join-Path $HOME 'git' }
  }
  if (-not (Test-Path -LiteralPath $Root)) { Write-Error "wt: no such directory: $Root"; return }
  $rows = @()
  foreach ($repo in Get-ChildItem -LiteralPath $Root -Directory -Filter *.git) {
    $repoName = $repo.Name -replace '\.git$', ''
    $path = $null
    $branch = 'detached'
    $skip = $false
    foreach ($line in @(git -C $repo.FullName worktree list --porcelain 2>$null) + '') {
      if ($line -eq '') {
        if (-not $skip -and $path) {
          $short = $path -replace '^.*[\\/]tuios[\\/]worktrees[\\/]', 'tuios/worktrees/'
          $rows += "$repoName  $branch  $short`t$path"
        }
        $path = $null
        $branch = 'detached'
        $skip = $false
      } elseif ($line -like 'worktree *') {
        $path = $line.Substring(9)
      } elseif ($line -like 'branch refs/heads/*') {
        $branch = $line.Substring(18)
      } elseif ($line -in 'bare', 'prunable') {
        $skip = $true
      }
    }
  }
  if ($rows.Count -eq 0) { Write-Error "wt: no worktrees under $Root"; return }
  $picked = $rows | Sort-Object | fzf --delimiter '\t' --with-nth 1 --reverse --height 40% --prompt 'worktree> '
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
