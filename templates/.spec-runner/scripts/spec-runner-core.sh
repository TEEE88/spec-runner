#!/usr/bin/env bash
# spec-runner 判定の単一入口（薄いオーケストレータ）
# 使用: spec-runner-core.sh [--phase] [--json] | --status

set -e

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
STEPS_DIR="${STEPS_DIR:-$REPO_ROOT/.spec-runner/steps}"
STEPS_JSON="${STEPS_JSON:-$STEPS_DIR/steps.json}"
LOCK_FILE=".spec-runner/phase-locks.json"
PROJECT_JSON=".spec-runner/project.json"

die() { echo "$1" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "spec-runner-core: $1 が必要です"; }
require_file() { [[ -f "$1" ]] || die "spec-runner-core: ファイルがありません: $1"; }

get_steps_common_doc() {
  local key="$1"
  local v
  v="$(jq -r --arg k "$key" '.common.docs[$k] // empty' "$STEPS_JSON" 2>/dev/null)"
  [[ -n "$v" && "$v" != "null" ]] || die "spec-runner-core: steps.json に common.docs.$key がありません"
  echo "$v"
}

MODE="phase"
JSON_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) MODE="phase" ;;
    --json) JSON_MODE=true ;;
    --status) MODE="status" ;;
  esac
  shift
done

require_cmd jq
require_file "$PROJECT_JSON"
require_file "$STEPS_JSON"
require_file "$LOCK_FILE"

has_charter_lock=0
has_domain_lock=0
has_arch_lock=0
uc_discovery_completed=0
test_dir=""
test_pattern=""
require_uc_prefixed_tests=0

jq -e '.charter.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_charter_lock=1
jq -e '.domain.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_domain_lock=1
jq -e '.architecture.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_arch_lock=1
jq -e '.uc_discovery.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && uc_discovery_completed=1

test_dir=$(jq -r '.test_design.dir' "$PROJECT_JSON")
[[ -n "$test_dir" && "$test_dir" != "null" ]] || die "spec-runner-core: project.json test_design.dir が未設定です"
test_pattern=$(jq -r '.test_design.pattern' "$PROJECT_JSON")
[[ -n "$test_pattern" && "$test_pattern" != "null" ]] || die "spec-runner-core: project.json test_design.pattern が未設定です"
rq="$(jq -r '.test_design.require_uc_prefixed_tests // false' "$PROJECT_JSON")"
[[ "$rq" == "true" || "$rq" == "1" ]] && require_uc_prefixed_tests=1

quality_done() {
  local kind="$1"
  local scope="$2"
  local key="$3"
  local key_md="${key}.md"
  jq -e --arg k "$key" --arg km "$key_md" --arg s "$scope" \
    ".quality.${kind}[\$s][]? | select(. == \$k or . == \$km)" \
    "$LOCK_FILE" >/dev/null 2>&1
}

resolve_step() {
  local sid="$1"
  step_id="$sid"
  command=$(jq -r --arg id "$sid" '.steps[]? | select(.id==$id) | .name_ja' "$STEPS_JSON")
  local md
  md=$(jq -r --arg id "$sid" '.steps[]? | select(.id==$id) | .md_file' "$STEPS_JSON")
  [[ -n "$command" && "$command" != "null" ]] || die "spec-runner-core: steps.json に id=$sid の name_ja がありません"
  [[ -n "$md" && "$md" != "null" ]] || die "spec-runner-core: steps.json に id=$sid の md_file がありません"
  command_file="$STEPS_DIR/$md"
  step_commands=$(jq -c --arg id "$sid" '.steps[]? | select(.id==$id) | .commands' "$STEPS_JSON")
  check_command=$(jq -r '.common.commands.check' "$STEPS_JSON")
}

latest_uc_spec() {
  find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -type f -name "UC-*.md" 2>/dev/null | sort -V | tail -1
}

latest_unreviewed_uc_spec() {
  local f key
  while IFS= read -r f; do
    key="$(basename "$f" .md)"
    jq -e --arg u "$key" 'any(.uc_reviewed[]?; . == $u)' "$LOCK_FILE" >/dev/null 2>&1 && continue
    echo "$f"
    return 0
  done < <(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -type f -name "UC-*.md" 2>/dev/null | sort -V)
  return 1
}

uc_has_tests_ready_for_implement() {
  local uc_key="$1"
  local uc_id=""
  [[ -d "$test_dir" ]] || return 1
  if [[ $require_uc_prefixed_tests -eq 0 ]]; then
    [[ -n "$(find "$test_dir" -type f -name "$test_pattern" 2>/dev/null | head -1)" ]]
    return $?
  fi
  [[ "$uc_key" =~ ^(UC-[0-9]+)- ]] && uc_id="${BASH_REMATCH[1]}"
  [[ -n "$uc_id" ]] || return 1
  local f bn
  while IFS= read -r f; do
    bn=$(basename "$f")
    [[ "$bn" == "${uc_id}-"* ]] || continue
    [[ "$bn" == $test_pattern ]] || continue
    return 0
  done < <(find "$test_dir" -type f 2>/dev/null)
  return 1
}

run_status() {
  echo "=== spec-runner フェーズ状況 ==="
  echo "Lock（.spec-runner/phase-locks.json）:"
  for sec in charter domain architecture uc_discovery test_design; do
    if jq -e --arg s "$sec" '.[$s].completed == true' "$LOCK_FILE" >/dev/null 2>&1; then
      echo "  ✓ $sec"
    else
      echo "  - $sec"
    fi
  done
}

run_phase() {
  phase=0
  phase_name_ja=""
  command=""
  command_file=""
  step_id=""
  step_commands="[]"
  check_command=""
  feature_dir=""
  feature_spec=""
  charter_doc="$(get_steps_common_doc "charter")"
  domain_root="$(get_steps_common_doc "domain_root")"
  architecture_root="$(get_steps_common_doc "architecture_root")"
  domain_spec_present=0
  arch_spec_present=0

  doc_key() { basename "$1" .md; }
  first_md_in_dir() {
    local d="$1"
    [[ -d "$d" ]] || return 1
    find "$d" -type f -name "*.md" 2>/dev/null | sort | head -1
  }

  uc_count_total=$(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -name "UC-*.md" 2>/dev/null | wc -l | tr -d ' ')
  uc_count_total=${uc_count_total:-0}
  [[ -n "$(first_md_in_dir "$domain_root" || true)" ]] && domain_spec_present=1
  [[ -n "$(first_md_in_dir "$architecture_root" || true)" ]] && arch_spec_present=1

  # lock が先に立っていても、設計成果物が無い場合は必ず設計フェーズへ戻す
  [[ $domain_spec_present -eq 0 ]] && has_domain_lock=0
  [[ $arch_spec_present -eq 0 ]] && has_arch_lock=0
  # charter.completed が true でも、憲章成果物（docs/01_憲章/憲章.md）が無ければ Phase 0 に戻す
  [[ $has_charter_lock -eq 1 && ! -f "$charter_doc" ]] && has_charter_lock=0

  if [[ $has_charter_lock -eq 0 ]]; then
    if [[ -f "$charter_doc" ]]; then
      ckey="$(doc_key "$charter_doc")"
      feature_spec="$charter_doc"
      feature_dir="$(dirname "$charter_doc")"
      if ! quality_done "clarified" "charter" "$ckey"; then
        phase=0; phase_name_ja="憲章（曖昧さ解消）"; resolve_step "clarify"
      elif ! quality_done "analyzed" "charter" "$ckey"; then
        phase=0; phase_name_ja="憲章（分析）"; resolve_step "analyze"
      else
        phase=0; phase_name_ja="憲章策定"; resolve_step "charter"
      fi
    else
      phase=0; phase_name_ja="憲章策定"; resolve_step "charter"
    fi
  elif [[ $uc_discovery_completed -eq 0 ]]; then
    uc_spec="$(latest_unreviewed_uc_spec || true)"
    if [[ -n "$uc_spec" ]]; then
      feature_spec="$uc_spec"
      feature_dir="$(dirname "$uc_spec")"
      uc_key="$(doc_key "$uc_spec")"
      if ! quality_done "clarified" "uc" "$uc_key"; then
        phase=1; phase_name_ja="ユースケース洗い出し中（曖昧さ解消）"; resolve_step "clarify"
      elif ! quality_done "analyzed" "uc" "$uc_key"; then
        phase=1; phase_name_ja="ユースケース洗い出し中（分析）"; resolve_step "analyze"
      else
        phase=1; phase_name_ja="ユースケース洗い出し中（レビュー通過待ち）"; resolve_step "clarify"
      fi
    else
      phase=1; phase_name_ja="ユースケース洗い出し中（次UC作成）"; resolve_step "uc_spec"
    fi
  elif [[ $has_domain_lock -eq 0 ]]; then
    uc_spec="$(latest_unreviewed_uc_spec || true)"
    if [[ -n "$uc_spec" ]]; then
      feature_spec="$uc_spec"
      feature_dir="$(dirname "$uc_spec")"
      uc_key="$(doc_key "$uc_spec")"
      if ! quality_done "clarified" "uc" "$uc_key"; then
        phase=1; phase_name_ja="ユースケース仕様（曖昧さ解消）"; resolve_step "clarify"
      elif ! quality_done "analyzed" "uc" "$uc_key"; then
        phase=1; phase_name_ja="ユースケース仕様（分析）"; resolve_step "analyze"
      else
        phase=1; phase_name_ja="ユースケース仕様（レビュー通過まで）"; resolve_step "clarify"
      fi
    else
      domain_spec="$(first_md_in_dir "$domain_root" || true)"
      if [[ -n "$domain_spec" ]]; then
        feature_spec="$domain_spec"
        feature_dir="$(dirname "$domain_spec")"
        dkey="$(doc_key "$domain_spec")"
        if ! quality_done "clarified" "domain" "$dkey"; then
          phase=2; phase_name_ja="ドメイン設計（曖昧さ解消）"; resolve_step "clarify"
        elif ! quality_done "analyzed" "domain" "$dkey"; then
          phase=2; phase_name_ja="ドメイン設計（分析）"; resolve_step "analyze"
        else
          phase=2; phase_name_ja="ドメイン設計"; resolve_step "domain"
        fi
      else
        phase=2; phase_name_ja="ドメイン設計"; resolve_step "domain"
      fi
    fi
  elif [[ $has_arch_lock -eq 0 ]]; then
    arch_spec="$(first_md_in_dir "$architecture_root" || true)"
    if [[ -n "$arch_spec" ]]; then
      feature_spec="$arch_spec"
      feature_dir="$(dirname "$arch_spec")"
      akey="$(doc_key "$arch_spec")"
      if ! quality_done "clarified" "architecture" "$akey"; then
        phase=3; phase_name_ja="実装計画（曖昧さ解消）"; resolve_step "clarify"
      elif ! quality_done "analyzed" "architecture" "$akey"; then
        phase=3; phase_name_ja="実装計画（分析）"; resolve_step "analyze"
      else
        phase=3; phase_name_ja="実装計画"; resolve_step "architecture_plan"
      fi
    else
      phase=3; phase_name_ja="実装計画"; resolve_step "architecture_plan"
    fi
  else
    uc_spec="$(latest_uc_spec || true)"
    if [[ -z "$uc_spec" ]]; then
      phase=1; phase_name_ja="ユースケース仕様"; resolve_step "uc_spec"
    else
      feature_spec="$uc_spec"
      feature_dir="$(dirname "$uc_spec")"
      uc_key="$(doc_key "$uc_spec")"
      reviewed=0
      jq -e --arg u "$uc_key" 'any(.uc_reviewed[]?; . == $u)' "$LOCK_FILE" >/dev/null 2>&1 && reviewed=1
      if [[ $reviewed -eq 0 ]]; then
        if ! quality_done "clarified" "uc" "$uc_key"; then
          phase=1; phase_name_ja="ユースケース仕様（曖昧さ解消）"; resolve_step "clarify"
        elif ! quality_done "analyzed" "uc" "$uc_key"; then
          phase=1; phase_name_ja="ユースケース仕様（分析）"; resolve_step "analyze"
        else
          phase=1; phase_name_ja="ユースケース仕様（レビュー通過まで）"; resolve_step "clarify"
        fi
      else
        if uc_has_tests_ready_for_implement "$uc_key"; then
          phase=6; phase_name_ja="実装"; resolve_step "implement"
        else
          phase=5; phase_name_ja="テスト設計"; resolve_step "test_design"
        fi
      fi
    fi
  fi

  if [[ "$JSON_MODE" == true ]]; then
    jq -cn --argjson phase "$phase" --arg name "$phase_name_ja" --arg step_id "$step_id" --arg cmd "$command" --arg file "$command_file" \
      --arg check "$check_command" --argjson cmds "$step_commands" \
      --arg feature_dir "$feature_dir" --arg feature_spec "$feature_spec" \
      '{phase:$phase, phase_name_ja:$name, step_id:$step_id, command:$cmd, command_file:$file, check_command:$check, step_commands:$cmds, feature_dir:$feature_dir, feature_spec:$feature_spec}'
  else
    echo "現在フェーズ: Phase $phase（$phase_name_ja）"
    echo "推奨コマンド: $command"
    echo "コマンドファイル: $command_file"
    echo "チェック（毎回）: $check_command"
  fi
}

if [[ "$MODE" == "status" ]]; then
  run_status
else
  run_phase
fi
