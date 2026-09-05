#!/bin/sh
# Emit only allowlisted metadata from one exact Codex rollout.

set -eu

usage() {
  cat <<'EOF'
Usage: inspect-agent-runtime.sh [--sessions-dir DIR] [--usage] THREAD_ID
       inspect-agent-runtime.sh [--sessions-dir DIR] [--usage] --primary THREAD_ID

Read the unique rollout whose filename ends with the lowercase UUID THREAD_ID and
emit allowlisted runtime metadata as compact JSON. A child rollout must contain an
agent_role. --primary permits a root rollout without one.

Options:
  --sessions-dir DIR  Use an explicit sessions root.
  --primary THREAD_ID Inspect a primary rollout, which may omit agent_role.
  --usage              Add aggregate counts from the latest token_count event.
                       If no count exists, usage is null.
  --help               Show this help text.
EOF
}

fail() {
  printf '%s\n' "ERROR: $*" >&2
  exit 1
}

sessions_dir=''
thread_id=''
primary=0
include_usage=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --sessions-dir)
      [ "$#" -ge 2 ] || fail "--sessions-dir requires a directory."
      [ -n "$2" ] || fail "--sessions-dir requires a non-empty directory."
      case "$2" in --*) fail "--sessions-dir requires a directory, not an option." ;; esac
      sessions_dir=$2
      shift 2
      ;;
    --primary)
      [ "$primary" -eq 0 ] || fail "--primary may be specified only once."
      [ -z "$thread_id" ] || fail "specify exactly one THREAD_ID."
      primary=1
      shift
      # Accept both `--primary THREAD_ID` and `--primary --usage THREAD_ID`.
      if [ "$#" -gt 0 ]; then
        case "$1" in
          --*) ;;
          *) thread_id=$1; shift ;;
        esac
      fi
      ;;
    --usage)
      include_usage=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*) fail "unknown argument: $1 (run with --help for usage)." ;;
    *)
      [ -z "$thread_id" ] || fail "specify exactly one THREAD_ID."
      thread_id=$1
      shift
      ;;
  esac
done

[ -n "$thread_id" ] || {
  usage >&2
  exit 2
}
if ! printf '%s\n' "$thread_id" | LC_ALL=C grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  fail "THREAD_ID must be a lowercase UUID."
fi

if [ -z "$sessions_dir" ]; then
  if [ -n "${CODEX_HOME-}" ]; then
    sessions_dir=$CODEX_HOME/sessions
  else
    [ -n "${HOME-}" ] ||
      fail "HOME is unset and CODEX_HOME was not supplied; pass --sessions-dir explicitly."
    sessions_dir=$HOME/.codex/sessions
  fi
fi
[ -d "$sessions_dir" ] && [ ! -L "$sessions_dir" ] ||
  fail "sessions directory is unavailable or unsafe."

tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in /*) ;; *) tmp_base=/tmp ;; esac
matches_file=''
cleanup() {
  if [ -n "$matches_file" ] && [ -f "$matches_file" ]; then
    case "$matches_file" in
      "$tmp_base"/astra-advisor-runtime.*) rm -f "$matches_file" ;;
      *) printf '%s\n' "ERROR: refusing cleanup of unexpected temporary file." >&2 ;;
    esac
  fi
}
trap cleanup 0 HUP INT TERM

matches_file=$(mktemp "$tmp_base/astra-advisor-runtime.XXXXXX") ||
  fail "could not create a temporary match list."
if ! find "$sessions_dir" -type f -name "rollout-*-$thread_id.jsonl" -print > "$matches_file"; then
  fail "could not enumerate rollout filenames under the sessions directory."
fi
match_count=$(awk 'END { print NR + 0 }' "$matches_file")
case "$match_count" in
  0) fail "no rollout filename matched the requested thread id." ;;
  1) ;;
  *) fail "multiple rollout filenames matched the requested thread id." ;;
esac

IFS= read -r rollout_file < "$matches_file" || fail "could not read the matched rollout filename."
[ -f "$rollout_file" ] && [ ! -L "$rollout_file" ] ||
  fail "matched rollout is unavailable or unsafe."

# Construct a new object rather than forwarding payloads. Codex rollout files are
# append-only, so the final turn_context and token_count carry the current values.
if ! jq -ce -s \
  --arg expected_thread_id "$thread_id" \
  --argjson primary "$primary" \
  --argjson include_usage "$include_usage" '
  def string_or_null:
    if type == "string" then . else null end;
  def count_or_null:
    if . == null then null
    elif type == "number" and . >= 0 and floor == . then .
    else error("invalid token count")
    end;

  [ .[] | select(.type == "session_meta") | .payload ] as $sessions |
  [ .[] | select(.type == "turn_context") | .payload ] as $turns |
  [ .[] |
    select(.type == "event_msg" and .payload.type == "token_count") |
    .payload.info.total_token_usage? |
    select(type == "object")
  ] as $token_totals |
  if ($sessions | length) != 1 then
    error("missing or ambiguous session metadata")
  elif ($turns | length) == 0 then
    error("missing turn context")
  else
    $sessions[0] as $session |
    $turns[-1] as $turn |
    ($session.id? | string_or_null) as $session_thread_id |
    ($session.source? |
      if type == "object" then (.subagent.thread_spawn? // null) else null end
    ) as $spawn |
    ($session.parent_thread_id? | string_or_null) as $direct_parent_thread_id |
    (($spawn // {}) | .parent_thread_id? | string_or_null) as $source_parent_thread_id |
    ($session.agent_role? | string_or_null) as $direct_agent_role |
    (($spawn // {}) | .agent_role? | string_or_null) as $source_agent_role |
    ($session.agent_path? | string_or_null) as $direct_agent_path |
    (($spawn // {}) | .agent_path? | string_or_null) as $source_agent_path |
    ($direct_parent_thread_id // $source_parent_thread_id) as $parent_thread_id |
    ($direct_agent_role // $source_agent_role) as $agent_role |
    ($direct_agent_path // $source_agent_path) as $agent_path |
    ($session.model_provider? | string_or_null) as $model_provider |
    ($session.cwd? | string_or_null) as $session_cwd |
    ($turn.model? | string_or_null) as $model |
    ($turn.effort? | string_or_null) as $effort |
    ($turn.cwd? | string_or_null) as $cwd |
    (($turn.sandbox_policy? // {}) | .type? | string_or_null) as $sandbox_type |
    (($turn.permission_profile? // {}) | .type? | string_or_null) as $permission_type |
    if $session_thread_id != $expected_thread_id then
      error("session metadata does not identify the requested thread")
    elif $direct_parent_thread_id != null and $source_parent_thread_id != null
      and $direct_parent_thread_id != $source_parent_thread_id then
      error("conflicting parent thread ids")
    elif $direct_agent_role != null and $source_agent_role != null
      and $direct_agent_role != $source_agent_role then
      error("conflicting agent roles")
    elif $direct_agent_path != null and $source_agent_path != null
      and $direct_agent_path != $source_agent_path then
      error("conflicting agent paths")
    elif $model == null or $model == "" then
      error("missing model")
    elif $effort == null or $effort == "" then
      error("missing effort")
    elif $cwd == null or $cwd == "" then
      error("missing working directory")
    elif $session_cwd != null and $session_cwd != $cwd then
      error("conflicting working directories")
    elif $primary == 0 and ($agent_role == null or $agent_role == "") then
      error("missing child agent role")
    else
      {
        thread_id: $session_thread_id,
        parent_thread_id: $parent_thread_id,
        agent_role: $agent_role,
        agent_path: $agent_path,
        model_provider: $model_provider,
        model: $model,
        effort: $effort,
        sandbox_policy_type: $sandbox_type,
        permission_profile_type: $permission_type,
        cwd: $cwd
      }
      + if $include_usage == 1 then
          {
            usage:
              if ($token_totals | length) == 0 then null
              else $token_totals[-1] as $usage | {
                input_tokens: ($usage.input_tokens? | count_or_null),
                cached_input_tokens: ($usage.cached_input_tokens? | count_or_null),
                cache_write_input_tokens: ($usage.cache_write_input_tokens? | count_or_null),
                output_tokens: ($usage.output_tokens? | count_or_null),
                reasoning_output_tokens: ($usage.reasoning_output_tokens? | count_or_null),
                total_tokens: ($usage.total_tokens? | count_or_null)
              }
              end
          }
        else {}
        end
    end
  end
' "$rollout_file" 2>/dev/null; then
  fail "rollout is missing, ambiguous, invalid, or inconsistent required runtime metadata."
fi
