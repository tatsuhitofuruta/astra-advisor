#!/bin/sh
# Install Astra Advisor's two custom-agent profiles without changing Codex config.

set -eu

usage() {
  cat <<'EOF'
Usage: install-agents.sh [--target-dir PATH] [--check] [--check-role ROLE ...]

Install Astra Advisor's implementer and reviewer profiles into the target directory.
Existing files are accepted only when they exactly match the shipped profile. This
script never changes Sol Advisor profiles or any other files in the target directory.

Without --target-dir, the target is "$CODEX_HOME/agents" when CODEX_HOME is set,
otherwise "$HOME/.codex/agents".

Options:
  --target-dir PATH  Use an explicit destination directory.
  --check            Check both profiles without changing the filesystem.
  --check-role ROLE  Check only implementer or reviewer; repeatable. Implies --check.
  --help             Show this help text.
EOF
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

report_error() {
  printf '%s\n' "ERROR: $*" >&2
  preflight_failed=1
}

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

classify_destination() {
  destination=$1
  template=$2
  if ! path_exists "$destination"; then
    printf '%s\n' missing
  elif [ -L "$destination" ] || [ ! -f "$destination" ]; then
    printf '%s\n' unsafe
  elif cmp -s "$template" "$destination"; then
    printf '%s\n' current
  else
    printf '%s\n' conflict
  fi
}

role_selected() {
  selected_role=$1
  if [ -z "$check_roles" ]; then
    return 0
  fi
  case ",$check_roles," in
    *,"$selected_role",*) return 0 ;;
    *) return 1 ;;
  esac
}

install_missing() {
  template=$1
  destination=$2
  staged=''
  path_exists "$destination" &&
    fail "destination changed after preflight and will not be overwritten: $destination"
  staged=$(mktemp "$target_dir/.astra-advisor-agent.XXXXXX") ||
    fail "could not stage profile: $destination"
  if ! cp "$template" "$staged"; then
    rm -f "$staged"
    fail "could not stage profile: $destination"
  fi
  if ! ln "$staged" "$destination"; then
    rm -f "$staged"
    fail "destination changed after preflight and will not be overwritten: $destination"
  fi
  rm -f "$staged" || fail "could not remove staged profile: $staged"
  printf '%s\n' "INSTALLED: $destination"
}

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
template_dir=$script_dir/../agents

if [ -n "${CODEX_HOME-}" ]; then
  target_dir=$CODEX_HOME/agents
else
  [ -n "${HOME-}" ] ||
    fail "HOME is unset and CODEX_HOME was not supplied; pass --target-dir explicitly."
  target_dir=$HOME/.codex/agents
fi

check_only=0
check_roles=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target-dir)
      [ "$#" -ge 2 ] || fail "--target-dir requires a path."
      [ -n "$2" ] || fail "--target-dir requires a non-empty path."
      case "$2" in --*) fail "--target-dir requires a path, not an option." ;; esac
      target_dir=$2
      shift 2
      ;;
    --check)
      check_only=1
      shift
      ;;
    --check-role)
      [ "$#" -ge 2 ] || fail "--check-role requires implementer or reviewer."
      case "$2" in
        implementer|reviewer) ;;
        *) fail "unknown --check-role '$2'; expected implementer or reviewer." ;;
      esac
      check_only=1
      check_roles=$check_roles$2,
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *) fail "unknown argument: $1 (run with --help for usage)." ;;
  esac
done

case "$target_dir" in
  /*) ;;
  *) target_dir=$(pwd -P)/$target_dir ;;
esac
# A trailing slash makes some `test -L` implementations dereference the final
# component. Remove all trailing slashes while preserving the filesystem root.
while [ "$target_dir" != / ] && [ "${target_dir%/}" != "$target_dir" ]; do
  target_dir=${target_dir%/}
done

implementer_file=astra-advisor-sol-implementer.toml
reviewer_file=astra-advisor-sol-reviewer.toml
implementer_template=$template_dir/$implementer_file
reviewer_template=$template_dir/$reviewer_file
implementer_destination=$target_dir/$implementer_file
reviewer_destination=$target_dir/$reviewer_file

for template in "$implementer_template" "$reviewer_template"; do
  [ -f "$template" ] && [ ! -L "$template" ] ||
    fail "shipped profile is missing or not a regular file: $template"
done

# Resolve predictable conflicts before creating the target or installing either file.
if path_exists "$target_dir"; then
  [ -d "$target_dir" ] && [ ! -L "$target_dir" ] ||
    fail "target directory is not a real directory: $target_dir"
  target_physical=$(CDPATH= cd "$target_dir" && pwd -P) ||
    fail "could not resolve target directory: $target_dir"
  [ "$target_physical" != / ] ||
    fail "refusing to use the filesystem root as an agent target directory."
else
  # `mkdir -p` can resolve dot segments through an existing ancestor and create a
  # different physical target than the spelling suggests. Require an unambiguous
  # missing path, then verify its physical location again after creation.
  case "/$target_dir/" in
    */./*|*/../*) fail "refusing a missing target directory with dot path segments: $target_dir" ;;
  esac
fi
implementer_state=$(classify_destination "$implementer_destination" "$implementer_template")
reviewer_state=$(classify_destination "$reviewer_destination" "$reviewer_template")
preflight_failed=0

if [ "$check_only" -eq 1 ]; then
  if role_selected implementer && [ "$implementer_state" != current ]; then
    report_error "implementer profile is $implementer_state, not an exact match: $implementer_destination"
  fi
  if role_selected reviewer && [ "$reviewer_state" != current ]; then
    report_error "reviewer profile is $reviewer_state, not an exact match: $reviewer_destination"
  fi
else
  case "$implementer_state" in
    current|missing) ;;
    *) report_error "implementer destination is $implementer_state and will not be replaced: $implementer_destination" ;;
  esac
  case "$reviewer_state" in
    current|missing) ;;
    *) report_error "reviewer destination is $reviewer_state and will not be replaced: $reviewer_destination" ;;
  esac
fi
[ "$preflight_failed" -eq 0 ] || exit 1

if [ "$check_only" -eq 1 ]; then
  printf '%s\n' "CHECK PASSED: selected Astra Advisor profiles match exactly."
  exit 0
fi

if [ ! -d "$target_dir" ]; then
  mkdir -p "$target_dir" || fail "could not create target directory: $target_dir"
fi
[ -d "$target_dir" ] && [ ! -L "$target_dir" ] ||
  fail "target directory changed after preflight: $target_dir"
target_physical=$(CDPATH= cd "$target_dir" && pwd -P) ||
  fail "could not resolve target directory after creation: $target_dir"
[ "$target_physical" != / ] ||
  fail "refusing to use the filesystem root as an agent target directory."

[ "$(classify_destination "$implementer_destination" "$implementer_template")" = "$implementer_state" ] ||
  fail "implementer destination changed after preflight; no profiles were installed."
[ "$(classify_destination "$reviewer_destination" "$reviewer_template")" = "$reviewer_state" ] ||
  fail "reviewer destination changed after preflight; no profiles were installed."

case "$implementer_state" in
  missing) install_missing "$implementer_template" "$implementer_destination" ;;
  current) printf '%s\n' "ALREADY CURRENT: $implementer_destination" ;;
esac
case "$reviewer_state" in
  missing) install_missing "$reviewer_template" "$reviewer_destination" ;;
  current) printf '%s\n' "ALREADY CURRENT: $reviewer_destination" ;;
esac

cmp -s "$implementer_template" "$implementer_destination" ||
  fail "post-install exactness check failed: $implementer_destination"
cmp -s "$reviewer_template" "$reviewer_destination" ||
  fail "post-install exactness check failed: $reviewer_destination"
printf '%s\n' "INSTALL PASSED: both Astra Advisor profiles match exactly."
