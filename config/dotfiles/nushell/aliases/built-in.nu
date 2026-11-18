# Alias support for `sudo`, see https://github.com/nushell/nushell/issues/17652
# NOTICE: Nushell built-in commands or Aliases to them are not supported.
export def --wrapped sudo [...args] {
  ^sudo ...(match $args {
    [$first, ..$rest] => {
      # Only apply to first command not starts with "-", "/", or contains "="
      if not (($first | str starts-with "-") or ($first | str starts-with "/") or ($first | str contains "=")) {
        if (which $first).0?.type == alias {
          # Handle alias
          let definition = which $first | get 0.definition
          let tokens = $definition | split row " "
          let full_path = which $tokens.0 | get 0.path
          [$full_path] | append ($tokens | skip 1) | append $rest
        } else {
          # Handle commands
          try {
            let path = (which $first).0.path
            if ($path | str length) > 0 { [$path] | append $rest } else { $args }
          } catch { $args }
        }
      } else { $args }
    },
    _ => $args
  })
}

export alias ll = ls --long
export alias la = ls --all

export alias cls = clear

# Return the readtime of given `filepath`.
#
# The default WPM (words per minute) is `200`,
# you can use `$env.READTIME_WPM` to override it.
export def readtime [filepath: string] {
  const default_wpm = 200
  let words = open $filepath --raw | str stats | get words
  if ($env.READTIME_WPM? | is-empty) {
    print $'≈ ($words / $default_wpm | math round) min <WPM: ($default_wpm)>'
  } else {
    print $'≈ ($words / $env.READTIME_WPM | math round) min <WPM: ($env.READTIME_WPM)>'
  }
}
