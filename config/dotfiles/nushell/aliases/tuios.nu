# `tuios wt ...` is `tuios worktree ...` (tuios has no subcommand aliases).
export def --wrapped tuios [...args] {
  if (($args | length) > 0) and ($args.0 == "wt") {
    ^tuios worktree ...($args | skip 1)
  } else {
    ^tuios ...$args
  }
}

# Short name for tuios. Defined after the command above so the alias resolves
# to it, and `tos wt ...` works too.
export alias tos = tuios
