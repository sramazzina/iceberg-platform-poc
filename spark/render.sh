# render_template for the spark image. Copy of aws/lib.sh, because the image build
# context is spark/. Source this file; do not run it.

# render_template FILE
# Prints FILE with every ${NAME} placeholder replaced by the value of the shell
# variable NAME. Returns 1 when a placeholder has no value.
render_template() {
  local content name
  content=$(<"$1")
  while [[ $content =~ \$\{([A-Z_][A-Z0-9_]*)\} ]]; do
    name=${BASH_REMATCH[1]}
    if [[ -z ${!name:-} ]]; then
      echo "render_template: variable $name is not set (in $1)" >&2
      return 1
    fi
    if [[ ${!name} == *'${'* ]]; then
      echo "render_template: value of $name contains '\${' (in $1)" >&2
      return 1
    fi
    content=${content//"\${$name}"/"${!name}"}
  done
  printf '%s\n' "$content"
}
