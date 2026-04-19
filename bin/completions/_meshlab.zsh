#compdef meshlab
#
# Zsh completion for the `meshlab` CLI (bin/meshlab).
#
# Completes top-level subcommands and, for `meshlab run`, the list of
# sections returned by `meshlab list` so completion never drifts from
# the SECTIONS array defined in the script itself.

_meshlab() {
  local -a subcommands sections counts
  local state

  subcommands=(
    'create:Create clusters and run all sections (optional WLCNT)'
    'delete:Tear down clusters and clean up'
    'watch:Watch cluster state via `ml short`'
    'list:List all available sections'
    'run:Run a single section (run <section> [count])'
  )

  _arguments -C \
    '1: :->cmd' \
    '2: :->arg2' \
    '3: :->arg3' \
    && return

  case $state in
    cmd)
      _describe -t commands 'meshlab subcommand' subcommands
      ;;
    arg2)
      case ${words[2]} in
        run)
          sections=(${(f)"$(command meshlab list 2>/dev/null)"})
          _describe -t sections 'section' sections
          ;;
        create)
          counts=(1 2)
          _describe -t counts 'workload count' counts
          ;;
      esac
      ;;
    arg3)
      if [[ ${words[2]} == run ]]; then
        counts=(1 2)
        _describe -t counts 'workload count' counts
      fi
      ;;
  esac
}

compdef _meshlab meshlab
