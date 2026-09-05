#!/bin/sh
# Focused repository-local verification for Astra Advisor's script layer.

set -eu

pass() { printf '%s\n' "PASS: $*"; }
fail() { printf '%s\n' "FAIL: $*" >&2; exit 1; }
expect_fail() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd) || exit 1
plugin_dir=$(CDPATH= cd "$script_dir/.." && pwd) || exit 1
installer=$script_dir/install-agents.sh
inspector=$script_dir/inspect-agent-runtime.sh
profiles=$plugin_dir/agents
implementer=astra-advisor-sol-implementer.toml
reviewer=astra-advisor-sol-reviewer.toml

tmp_base=${TMPDIR:-/tmp}
case "$tmp_base" in /*) ;; *) tmp_base=/tmp ;; esac
tmp_dir=''
cleanup() {
  if [ -n "$tmp_dir" ] && [ -d "$tmp_dir" ]; then
    case "$tmp_dir" in
      "$tmp_base"/astra-advisor-verify.*) rm -rf "$tmp_dir" ;;
      *) printf '%s\n' "REFUSING cleanup of unexpected directory: $tmp_dir" >&2 ;;
    esac
  fi
}
trap cleanup 0 HUP INT TERM
tmp_dir=$(mktemp -d "$tmp_base/astra-advisor-verify.XXXXXX") ||
  fail "could not create disposable verification directory"

snapshot() {
  target=$1
  if [ ! -d "$target" ]; then
    printf '%s\n' MISSING
    return
  fi
  find "$target" -mindepth 1 -maxdepth 1 -print | LC_ALL=C sort |
    while IFS= read -r path; do
      if [ -L "$path" ]; then
        printf 'L %s -> %s\n' "$(basename "$path")" "$(readlink "$path")"
      elif [ -f "$path" ]; then
        shasum -a 256 "$path"
      else
        printf 'O %s\n' "$(basename "$path")"
      fi
    done
}

expect_root_refusal() {
  root_alias=$1
  error_file=$tmp_dir/root-refusal-error
  if sh "$installer" --check --target-dir "$root_alias" > /dev/null 2> "$error_file"; then
    fail "root alias was accepted: $root_alias"
  fi
  grep -Fq 'refusing to use the filesystem root as an agent target directory.' "$error_file" ||
    fail "root alias did not produce the specific root-refusal error: $root_alias"
}

for required in "$installer" "$inspector" "$profiles/$implementer" "$profiles/$reviewer"; do
  [ -f "$required" ] || fail "required file missing: $required"
done
python3 - "$profiles" <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
expected = {
    "astra-advisor-sol-implementer.toml": {
        "name": "astra_advisor_sol_implementer",
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
    },
    "astra-advisor-sol-reviewer.toml": {
        "name": "astra_advisor_sol_reviewer",
        "model": "gpt-5.6-sol",
        "model_reasoning_effort": "high",
        "sandbox_mode": "read-only",
    },
}
actual = {path.name for path in root.glob("*.toml")}
if actual != set(expected):
    raise SystemExit(f"expected exactly {sorted(expected)}, found {sorted(actual)}")
for filename, fields in expected.items():
    data = tomllib.loads((root / filename).read_text(encoding="utf-8"))
    for required in ("name", "description", "developer_instructions"):
        if not isinstance(data.get(required), str) or not data[required].strip():
            raise SystemExit(f"{filename}: invalid {required}")
    for field, value in fields.items():
        if data.get(field) != value:
            raise SystemExit(f"{filename}: {field}={data.get(field)!r}, expected {value!r}")
PY
pass "two parseable, role-pinned profiles"

clean=$tmp_dir/clean
mkdir -p "$clean"
printf '%s\n' keep > "$clean/sol-advisor-sol-reviewer.toml"
sh "$installer" --target-dir "$clean" >/dev/null
cmp -s "$profiles/$implementer" "$clean/$implementer" || fail "implementer install mismatch"
cmp -s "$profiles/$reviewer" "$clean/$reviewer" || fail "reviewer install mismatch"
[ "$(cat "$clean/sol-advisor-sol-reviewer.toml")" = keep ] || fail "Sol Advisor file changed"
sh "$installer" --target-dir "$clean" --check >/dev/null
before=$(snapshot "$clean")
sh "$installer" --target-dir "$clean" >/dev/null
after=$(snapshot "$clean")
[ "$before" = "$after" ] || fail "idempotent install changed destination"
pass "clean install, exact check, idempotence, and Sol Advisor isolation"

selective=$tmp_dir/selective
sh "$installer" --target-dir "$selective" >/dev/null
printf '%s\n' modified >> "$selective/$reviewer"
before=$(snapshot "$selective")
sh "$installer" --target-dir "$selective" --check-role implementer >/dev/null
expect_fail sh "$installer" --target-dir "$selective" --check-role reviewer
expect_fail sh "$installer" --target-dir "$selective" --check
expect_fail sh "$installer" --target-dir "$selective" --check-role unknown
after=$(snapshot "$selective")
[ "$before" = "$after" ] || fail "check or invalid role mutated destination"
pass "role-selective checks and invalid-role refusal"

conflict=$tmp_dir/conflict
mkdir -p "$conflict"
printf '%s\n' local-change > "$conflict/$implementer"
before=$(snapshot "$conflict")
expect_fail sh "$installer" --target-dir "$conflict"
after=$(snapshot "$conflict")
[ "$before" = "$after" ] || fail "conflict caused partial mutation"
[ ! -e "$conflict/$reviewer" ] || fail "reviewer installed after implementer conflict"

unsafe=$tmp_dir/unsafe
mkdir -p "$unsafe"
ln -s "$profiles/$implementer" "$unsafe/$implementer"
before=$(snapshot "$unsafe")
expect_fail sh "$installer" --target-dir "$unsafe"
after=$(snapshot "$unsafe")
[ "$before" = "$after" ] || fail "symlink conflict caused partial mutation"
[ ! -e "$unsafe/$reviewer" ] || fail "reviewer installed after symlink conflict"

nonregular=$tmp_dir/nonregular
mkdir -p "$nonregular/$implementer"
before=$(snapshot "$nonregular")
expect_fail sh "$installer" --target-dir "$nonregular"
after=$(snapshot "$nonregular")
[ "$before" = "$after" ] || fail "nonregular conflict caused partial mutation"
[ ! -e "$nonregular/$reviewer" ] || fail "reviewer installed after nonregular conflict"

missing=$tmp_dir/missing
expect_fail sh "$installer" --target-dir "$missing" --check
[ ! -e "$missing" ] || fail "check created a missing target"
pass "conflict, symlink, nonregular, and missing-target failures are non-mutating"

# Use check mode exclusively: even a regression must not attempt root writes.
expect_root_refusal '///'
expect_root_refusal '/usr/..'

real_target=$tmp_dir/real-target
symlink_target=$tmp_dir/symlink-target
mkdir -p "$real_target"
ln -s "$real_target" "$symlink_target"
error_file=$tmp_dir/target-symlink-error
if sh "$installer" --check --target-dir "$symlink_target/" > /dev/null 2> "$error_file"; then
  fail "target symlink with trailing slash was accepted"
fi
grep -Fq 'target directory is not a real directory:' "$error_file" ||
  fail "target symlink with trailing slash did not produce the symlink refusal"
[ -z "$(find "$real_target" -mindepth 1 -maxdepth 1 -print -quit)" ] ||
  fail "target symlink check changed the symlink destination"

dot_target=$tmp_dir/not-created/..
error_file=$tmp_dir/dot-segment-error
if sh "$installer" --check --target-dir "$dot_target" > /dev/null 2> "$error_file"; then
  fail "missing target with dot segments was accepted"
fi
grep -Fq 'refusing a missing target directory with dot path segments:' "$error_file" ||
  fail "missing dot-segment target did not produce the specific refusal"
[ ! -e "$tmp_dir/not-created" ] || fail "dot-segment check created an intermediate directory"
pass "root aliases, trailing-slash target symlinks, and ambiguous missing paths fail before mutation"

fixture_config_root=$tmp_dir/config-root
mkdir -p "$fixture_config_root"
printf '%s\n' 'sentinel = "unchanged"' > "$fixture_config_root/config.toml"
sh "$installer" --target-dir "$fixture_config_root/agents" >/dev/null
cmp -s "$profiles/$implementer" "$fixture_config_root/agents/$implementer" ||
  fail "explicit-target implementer install mismatch"
cmp -s "$profiles/$reviewer" "$fixture_config_root/agents/$reviewer" ||
  fail "explicit-target reviewer install mismatch"
[ "$(cat "$fixture_config_root/config.toml")" = 'sentinel = "unchanged"' ] ||
  fail "installer changed adjacent config.toml"
pass "explicit target install preserves adjacent config"

sessions=$tmp_dir/sessions
day=$sessions/2026/09/05
mkdir -p "$day"

primary_id=11111111-1111-7111-8111-111111111111
primary_file=$day/rollout-2026-09-05T00-00-00-$primary_id.jsonl
cat > "$primary_file" <<EOF
{"type":"session_meta","payload":{"id":"$primary_id","model_provider":"openai","cwd":"/fixture","source":"vscode"}}
{"type":"response_item","payload":{"type":"message","content":"PRIMARY_SECRET"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"medium","cwd":"/fixture","sandbox_policy":{"type":"danger-full-access"},"permission_profile":{"type":"disabled"}}}
{"type":"turn_context","payload":{"model":"gpt-6-astra","effort":"high","cwd":"/fixture","sandbox_policy":{"type":"danger-full-access"},"permission_profile":{"type":"disabled"}}}
EOF
primary_output=$(sh "$inspector" --sessions-dir "$sessions" --primary "$primary_id")
printf '%s\n' "$primary_output" | jq -e --arg id "$primary_id" '
  .thread_id == $id and .agent_role == null and .model == "gpt-6-astra"
  and .effort == "high" and .cwd == "/fixture" and has("usage") == false
' >/dev/null || fail "primary runtime output is incorrect"
printf '%s\n' "$primary_output" | grep -Fq PRIMARY_SECRET && fail "primary output leaked message text"
expect_fail sh "$inspector" --sessions-dir "$sessions" "$primary_id"
pass "primary mode permits no role and uses the latest turn context"

child_id=22222222-2222-7222-8222-222222222222
parent_id=00000000-0000-7000-8000-000000000000
child_file=$day/rollout-2026-09-05T00-00-01-$child_id.jsonl
cat > "$child_file" <<EOF
{"type":"session_meta","payload":{"id":"$child_id","parent_thread_id":"$parent_id","agent_role":"astra_advisor_sol_implementer","agent_path":"/root/worker","model_provider":"openai","cwd":"/fixture","source":{"subagent":{"thread_spawn":{"parent_thread_id":"$parent_id","agent_role":"astra_advisor_sol_implementer","agent_path":"/root/worker","agent_nickname":"Fixture"}}}}}
{"type":"response_item","payload":{"type":"function_call_output","output":"CHILD_SECRET"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture","sandbox_policy":{"type":"danger-full-access","other":"hidden"},"permission_profile":{"type":"disabled","other":"hidden"}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":50,"cached_input_tokens":10,"cache_write_input_tokens":3,"output_tokens":5,"reasoning_output_tokens":2,"total_tokens":55,"price":999},"user_text":"TOKEN_SECRET"}}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":20,"reasoning_output_tokens":7,"total_tokens":120,"price":999},"user_text":"LATEST_SECRET"}}}
EOF
child_output=$(sh "$inspector" --sessions-dir "$sessions" "$child_id")
printf '%s\n' "$child_output" | jq -e --arg id "$child_id" --arg parent "$parent_id" '
  .thread_id == $id and .parent_thread_id == $parent
  and .agent_role == "astra_advisor_sol_implementer"
  and .model == "gpt-5.6-sol" and .effort == "high"
  and (keys | sort) == (["agent_path","agent_role","cwd","effort","model","model_provider","parent_thread_id","permission_profile_type","sandbox_policy_type","thread_id"] | sort)
' >/dev/null || fail "child runtime output is incorrect or not allowlisted"
printf '%s\n' "$child_output" | grep -Eq 'SECRET|price|other' && fail "child output leaked non-allowlisted data"

usage_output=$(sh "$inspector" --usage --sessions-dir "$sessions" "$child_id")
printf '%s\n' "$usage_output" | jq -e '
  .usage.input_tokens == 100 and .usage.cached_input_tokens == 80
  and .usage.cache_write_input_tokens == null
  and .usage.output_tokens == 20 and .usage.reasoning_output_tokens == 7
  and .usage.total_tokens == 120
  and (.usage | keys | sort) == (["cached_input_tokens","cache_write_input_tokens","input_tokens","output_tokens","reasoning_output_tokens","total_tokens"] | sort)
' >/dev/null || fail "usage did not use the latest aggregate token count"
printf '%s\n' "$usage_output" | grep -Eq 'SECRET|price|user_text' && fail "usage output leaked non-allowlisted data"
pass "child routing and latest aggregate usage are allowlisted"

negative_usage_id=88888888-8888-7888-8888-888888888888
cat > "$day/rollout-2026-09-05T00-00-08-$negative_usage_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$negative_usage_id","agent_role":"astra_advisor_sol_implementer","cwd":"/fixture"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":-1,"total_tokens":1}}}}
EOF
expect_fail sh "$inspector" --usage --sessions-dir "$sessions" "$negative_usage_id"

fractional_usage_id=99999999-9999-7999-8999-999999999999
cat > "$day/rollout-2026-09-05T00-00-09-$fractional_usage_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$fractional_usage_id","agent_role":"astra_advisor_sol_implementer","cwd":"/fixture"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1.5,"total_tokens":2.5}}}}
EOF
expect_fail sh "$inspector" --usage --sessions-dir "$sessions" "$fractional_usage_id"
pass "negative and noninteger token counts fail closed"

no_usage_output=$(sh "$inspector" --sessions-dir "$sessions" --primary --usage "$primary_id")
printf '%s\n' "$no_usage_output" | jq -e '.usage == null' >/dev/null ||
  fail "absent usage was not null"

missing_role_id=33333333-3333-7333-8333-333333333333
cat > "$day/rollout-2026-09-05T00-00-02-$missing_role_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$missing_role_id","cwd":"/fixture"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
EOF
expect_fail sh "$inspector" --sessions-dir "$sessions" "$missing_role_id"

missing_context_id=44444444-4444-7444-8444-444444444444
cat > "$day/rollout-2026-09-05T00-00-03-$missing_context_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$missing_context_id","agent_role":"astra_advisor_sol_reviewer","cwd":"/fixture"}}
EOF
expect_fail sh "$inspector" --sessions-dir "$sessions" "$missing_context_id"

conflict_id=55555555-5555-7555-8555-555555555555
cat > "$day/rollout-2026-09-05T00-00-04-$conflict_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$conflict_id","parent_thread_id":"$parent_id","agent_role":"astra_advisor_sol_implementer","cwd":"/fixture","source":{"subagent":{"thread_spawn":{"parent_thread_id":"$parent_id","agent_role":"astra_advisor_sol_reviewer"}}}}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
EOF
expect_fail sh "$inspector" --sessions-dir "$sessions" "$conflict_id"

duplicate_id=66666666-6666-7666-8666-666666666666
duplicate_file=$day/rollout-2026-09-05T00-00-05-$duplicate_id.jsonl
cat > "$duplicate_file" <<EOF
{"type":"session_meta","payload":{"id":"$duplicate_id","agent_role":"astra_advisor_sol_reviewer","cwd":"/fixture"}}
{"type":"session_meta","payload":{"id":"$duplicate_id","agent_role":"astra_advisor_sol_reviewer","cwd":"/fixture"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
EOF
expect_fail sh "$inspector" --sessions-dir "$sessions" "$duplicate_id"

ambiguous_id=77777777-7777-7777-8777-777777777777
for suffix in 06 07; do
  cat > "$day/rollout-2026-09-05T00-00-$suffix-$ambiguous_id.jsonl" <<EOF
{"type":"session_meta","payload":{"id":"$ambiguous_id","agent_role":"astra_advisor_sol_reviewer","cwd":"/fixture"}}
{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high","cwd":"/fixture"}}
EOF
done
expect_fail sh "$inspector" --sessions-dir "$sessions" "$ambiguous_id"
expect_fail sh "$inspector" --sessions-dir "$sessions" invalid
expect_fail sh "$inspector" --sessions-dir "$sessions" 22222222-2222-7222-8222-222222222223
pass "missing, conflicting, ambiguous, invalid, and unmatched runtime metadata fail closed"

sh -n "$installer"
sh -n "$inspector"
sh -n "$script_dir/verify.sh"
pass "shell syntax"
printf '%s\n' "VERIFY PASSED: Astra Advisor script checks completed."
