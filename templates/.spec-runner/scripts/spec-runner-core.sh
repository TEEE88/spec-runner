#!/usr/bin/env bash
# spec-runner 判定の単一入口。振る舞い仕様に沿って「フェーズ・ゲート・状態・グレード」を扱う。
# 使用: spec-runner-core.sh [--phase] [--json] | --gate [GRADE] | --status | --grade
# cmd-dispatch.sh（次のステップ・ゲート確認・ブランチ作成）から呼ばれる。

set -e

# ============================================================
# 0) 基本設定
# ============================================================
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
STEPS_DIR="${STEPS_DIR:-$REPO_ROOT/.spec-runner/steps}"
STEPS_JSON="${STEPS_JSON:-$STEPS_DIR/steps.json}"
LOCK_FILE=".spec-runner/phase-locks.json"
GRADE_FILE=".spec-runner/grade-history.json"
PROJECT_JSON=".spec-runner/project.json"

# ============================================================
# 1) ユーティリティ
# ============================================================
die() { echo "$1" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "spec-runner-core: $1 が必要です（例: brew install $1）"
}

require_file() {
  [[ -f "$1" ]] || die "spec-runner-core: ファイルがありません: $1"
}

get_steps_common_doc() {
  local key="$1"
  local v
  v="$(jq -r --arg k "$key" '.common.docs[$k] // empty' "$STEPS_JSON" 2>/dev/null)"
  [[ -n "$v" && "$v" != "null" ]] || die "spec-runner-core: steps.json に common.docs.$key がありません"
  echo "$v"
}

# ============================================================
# 2) 引数解析
# ============================================================
MODE="phase"
JSON_MODE=false
GATE_GRADE=""
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --phase)  MODE="phase" ;;
      --json)   JSON_MODE=true ;;
      --gate)   MODE="gate"; GATE_GRADE="${2:-}"; shift ;;
      --status) MODE="status" ;;
      --grade)  MODE="grade" ;;
      *)        [[ "$MODE" == "gate" && -z "$GATE_GRADE" ]] && GATE_GRADE="$1" ;;
    esac
    shift
  done
}
parse_args "$@"

# ============================================================
# 3) 前提チェック & 状態ロード（1回だけ）
# ============================================================
require_cmd jq
require_file "$PROJECT_JSON"
require_file "$STEPS_JSON"
require_file "$LOCK_FILE"
require_file "$GRADE_FILE"

has_charter_lock=0
has_domain_lock=0
has_arch_lock=0
has_infra_lock=0
uc_discovery_completed=0
grade=""
branch=""
test_dir=""
test_pattern=""
branch_prefix=""
uc_id_re=""
other_work_pattern=""
on_uc_branch=0
on_other_work_branch=0
current_uc_id=""

load_state() {
  jq -e '.charter.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_charter_lock=1
  jq -e '.domain.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_domain_lock=1
  jq -e '.architecture.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_arch_lock=1
  jq -e '.infra.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && has_infra_lock=1
  jq -e '.uc_discovery.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && uc_discovery_completed=1

  grade=$(jq -r '.current_grade' "$GRADE_FILE")
  [[ -n "$grade" && "$grade" != "null" ]] || die "spec-runner-core: grade-history.json の current_grade が未設定です"

  branch=$(git branch --show-current 2>/dev/null || echo "")

  branch_prefix=$(jq -r '.naming.branch_prefix' "$PROJECT_JSON")
  [[ -n "$branch_prefix" && "$branch_prefix" != "null" ]] || die "spec-runner-core: project.json naming.branch_prefix が未設定です"
  uc_id_re=$(jq -r '.naming.uc_id_pattern' "$PROJECT_JSON")
  [[ -n "$uc_id_re" && "$uc_id_re" != "null" ]] || die "spec-runner-core: project.json naming.uc_id_pattern が未設定です"
  other_work_pattern=$(jq -r '.naming.other_work_prefixes | join("|")' "$PROJECT_JSON")
  [[ -n "$other_work_pattern" ]] || die "spec-runner-core: project.json naming.other_work_prefixes が空です"

  test_dir=$(jq -r '.test_design.dir' "$PROJECT_JSON")
  [[ -n "$test_dir" && "$test_dir" != "null" ]] || die "spec-runner-core: project.json test_design.dir が未設定です"
  test_pattern=$(jq -r '.test_design.pattern' "$PROJECT_JSON")
  [[ -n "$test_pattern" && "$test_pattern" != "null" ]] || die "spec-runner-core: project.json test_design.pattern が未設定です"
  require_uc_prefixed_tests=1
  rq="$(jq -r '.test_design.require_uc_prefixed_tests // true' "$PROJECT_JSON")"
  [[ "$rq" == "false" || "$rq" == "0" ]] && require_uc_prefixed_tests=0

  if [[ "$branch" =~ ^${branch_prefix}/(${uc_id_re})- ]]; then
    on_uc_branch=1
    current_uc_id="${BASH_REMATCH[1]}"
  elif [[ "$branch" =~ ^${branch_prefix}/(${other_work_pattern})/ ]]; then
    on_other_work_branch=1
  fi
}
load_state

# UC ブランチで「実装に進める」ためのテスト存在判定（TDD: 当該 UC 用 spec を先に書かせる）
uc_branch_has_tests_ready_for_implement() {
  [[ -d "$test_dir" ]] || return 1
  if [[ $require_uc_prefixed_tests -eq 0 ]]; then
    [[ -n "$(find "$test_dir" -type f -name "$test_pattern" 2>/dev/null | head -1)" ]]
    return $?
  fi
  [[ -n "$current_uc_id" ]] || return 1
  local f bn
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    bn=$(basename "$f")
    [[ "$bn" == "${current_uc_id}-"* ]] || continue
    [[ "$bn" == $test_pattern ]] || continue
    return 0
  done < <(find "$test_dir" -type f 2>/dev/null)
  return 1
}

# ============================================================
# 4) ゲート関連（小関数）
# ============================================================
gate_error() { echo "GATE: $1" >&2; exit 1; }

resolve_steps_token() {
  local p="$1"
  [[ "$p" != steps:* ]] && { echo "$p"; return 0; }
  local token keypart suffix base
  token="${p#steps:}"
  keypart="${token%%/*}"
  suffix=""
  [[ "$token" == *"/"* ]] && suffix="/${token#*/}"
  base="$(jq -r --arg k "$keypart" '.common.docs[$k] // empty' "$STEPS_JSON")"
  [[ -n "$base" && "$base" != "null" ]] || gate_error "steps.json に common.docs.$keypart がありません（required_docs の $p を解決できません）"
  echo "${base}${suffix}"
}

get_required_docs_list() {
  local key="$1"
  jq -r --arg k "$key" '.required_docs[$k][]?' "$PROJECT_JSON"
}

assert_paths_exist() {
  local paths="$1"
  while IFS= read -r p; do
    [[ -z "$p" || "$p" == "null" ]] && continue
    p="$(resolve_steps_token "$p")"
    if [[ -f "$p" ]]; then
      :
    elif [[ -d "$p" ]]; then
      count=$(find "$p" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      [[ "${count:-0}" -ge 1 ]] || gate_error "必須: $p に 1 件以上の .md がありません"
    else
      gate_error "必須: $p が存在しません"
    fi
  done <<< "$paths"
}

gate_charter() {
  local list
  list="$(get_required_docs_list "charter")"
  [[ -n "$list" ]] || gate_error "project.json の required_docs.charter が未設定です"
  assert_paths_exist "$list"
  if [[ "$1" == "LOOP1" ]]; then
    jq -e '.charter.completed == true' "$LOCK_FILE" >/dev/null 2>&1 || gate_error "Phase 0 未完了（phase-locks.json の charter.completed）"
    jq -e '.charter.reviewed_by' "$LOCK_FILE" >/dev/null 2>&1 || gate_error "憲章に署名がありません（charter.reviewed_by）"
    echo "Phase 0: OK"
  fi
}

gate_domain_and_arch() {
  local grd="$1"
  [[ "$grd" == "LOOP1" ]] && return 0

  jq -e '.domain.completed == true' "$LOCK_FILE" >/dev/null 2>&1 || gate_error "Phase 1 未完了"
  list="$(get_required_docs_list "domain")"
  [[ -n "$list" ]] || gate_error "project.json の required_docs.domain が未設定です"
  assert_paths_exist "$list"
  echo "Phase 1: OK"

  jq -e '.architecture.completed == true' "$LOCK_FILE" >/dev/null 2>&1 || gate_error "Phase 2 未完了"
  list="$(get_required_docs_list "architecture")"
  [[ -n "$list" ]] || gate_error "project.json の required_docs.architecture が未設定です"
  assert_paths_exist "$list"
  echo "Phase 2: OK"
}

gate_infra_grade_a() {
  [[ "$1" != "A" ]] && return 0
  jq -e '.infra.completed == true' "$LOCK_FILE" >/dev/null 2>&1 || gate_error "Grade A: インフラ設計未完了"
  list="$(get_required_docs_list "grade_a")"
  [[ -n "$list" ]] || gate_error "project.json の required_docs.grade_a が未設定です（Grade A 時必須）"
  assert_paths_exist "$list"
  echo "Phase 4 (Grade A): OK"
}

gate_uc_openapi_and_tests() {
  local grd="$1"
  [[ "$grd" != "A" && "$grd" != "B" ]] && return 0

  uc_count=$(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -name "UC-*.md" 2>/dev/null | wc -l)
  if [[ "${uc_count:-0}" -gt 0 ]]; then
    uc_reviewed_count=$(jq '.uc_reviewed | length' "$LOCK_FILE")
    [[ "${uc_reviewed_count:-0}" -gt 0 ]] || gate_error "Gate 3: uc_reviewed に少なくとも1件の UC 識別子を登録してください"
    list="$(get_required_docs_list "gate3_openapi")"
    [[ -n "$list" ]] || gate_error "project.json の required_docs.gate3_openapi が未設定です"
    assert_paths_exist "$list"
    echo "Gate 3 (UC+OpenAPI): OK"
  fi

  test_design_ok=0
  jq -e '.test_design.completed == true' "$LOCK_FILE" >/dev/null 2>&1 && test_design_ok=1
  if [[ $test_design_ok -eq 1 ]] || [[ -d "$test_dir" && -n "$(find "$test_dir" -type f -name "$test_pattern" 2>/dev/null | head -1)" ]]; then
    echo "Gate 5 (テスト設計): OK"
  fi
}

gate_tests_green_soft() {
  local grd="$1"
  [[ "$grd" != "A" && "$grd" != "B" && "$grd" != "C" ]] && return 0

  if [[ -f ".spec-runner/scripts/test/require-tests-green.sh" ]]; then
    .spec-runner/scripts/test/require-tests-green.sh 2>/dev/null && echo "Gate 6 (テスト通過): OK" || true
  fi
}

# === ゲート確認モード ===
run_gate() {
  GRD="${GATE_GRADE:-$grade}"

  gate_charter "$GRD"
  gate_domain_and_arch "$GRD"
  gate_infra_grade_a "$GRD"
  gate_uc_openapi_and_tests "$GRD"
  gate_tests_green_soft "$GRD"

  echo "ゲート確認: 通過"
}

# === フェーズ判定モード ===
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

  first_md_in_dir() {
    local d="$1"
    [[ -d "$d" ]] || return 1
    find "$d" -type f -name "*.md" 2>/dev/null | sort | head -1
  }

  doc_key() {
    local f="$1"
    basename "$f" .md
  }

  quality_done() {
    local kind="$1"   # clarified | analyzed
    local scope="$2"  # charter | domain | architecture | uc
    local key="$3"
    # 互換性のため、quality には「ベース名」と「.md 付き」の両方を許容する
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
    [[ -n "$step_commands" && "$step_commands" != "null" ]] || die "spec-runner-core: steps.json に id=$sid の commands がありません"
    check_command=$(jq -r '.common.commands.check' "$STEPS_JSON")
    [[ -n "$check_command" && "$check_command" != "null" ]] || die "spec-runner-core: steps.json に common.commands.check がありません"
  }

  if [[ $on_uc_branch -eq 1 ]] && [[ -n "$current_uc_id" ]]; then
    for f in docs/02_ユースケース仕様/*/"${current_uc_id}-"*.md; do
      [[ -f "$f" ]] && feature_spec="$f" && feature_dir="$(dirname "$f")" && break
    done
  fi

  uc_count_total=$(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -name "UC-*.md" 2>/dev/null | wc -l | tr -d ' ')
  uc_count_total=${uc_count_total:-0}

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
  elif [[ $has_domain_lock -eq 0 && $on_uc_branch -eq 0 ]]; then
    # UC を洗い出している途中（uc_discovery.completed=false）の間はドメインへ進まない
    if [[ $uc_discovery_completed -eq 0 ]]; then
      phase=1; phase_name_ja="ユースケース洗い出し中（次UC作成）"; resolve_step "uc_spec"
    else
      # UC が 1 件以上ある場合のみ、ドメイン側の質フローを回す
      if [[ ${uc_count_total} -gt 0 ]]; then
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
      else
        phase=1; phase_name_ja="ユースケース洗い出し中（次UC作成）"; resolve_step "uc_spec"
      fi
    fi
  elif [[ $has_arch_lock -eq 0 && $has_domain_lock -eq 1 ]]; then
    arch_spec="$(first_md_in_dir "$architecture_root" || true)"
    if [[ -n "$arch_spec" ]]; then
      feature_spec="$arch_spec"
      feature_dir="$(dirname "$arch_spec")"
      akey="$(doc_key "$arch_spec")"
      if ! quality_done "clarified" "architecture" "$akey"; then
        phase=3; phase_name_ja="アーキテクチャ選択（曖昧さ解消）"; resolve_step "clarify"
      elif ! quality_done "analyzed" "architecture" "$akey"; then
        phase=3; phase_name_ja="アーキテクチャ選択（分析）"; resolve_step "analyze"
      else
        phase=3; phase_name_ja="アーキテクチャ選択"; resolve_step "architecture_plan"
      fi
    else
      phase=3; phase_name_ja="アーキテクチャ選択"; resolve_step "architecture_plan"
    fi
  elif [[ $on_uc_branch -eq 1 ]]; then
    uc_spec=""
    if [[ -n "$current_uc_id" ]]; then
      for f in docs/02_ユースケース仕様/*/"${current_uc_id}-"*.md; do [[ -f "$f" ]] && uc_spec="$f" && break; done
    fi
    if [[ -z "$uc_spec" ]]; then
      phase=1; phase_name_ja="ユースケース仕様"; resolve_step "uc_spec"
    else
      feature_spec="$uc_spec"
      feature_dir="$(dirname "$uc_spec")"
      uc_dir=$(basename "$uc_spec" .md)
      reviewed=0
      jq -e --arg u "$uc_dir" '.uc_reviewed[]? == $u' "$LOCK_FILE" 2>/dev/null | grep -q true && reviewed=1
      if [[ $reviewed -eq 0 ]]; then
        if ! quality_done "clarified" "uc" "$uc_dir"; then
          phase=1; phase_name_ja="ユースケース仕様（曖昧さ解消）"; resolve_step "clarify"
        elif ! quality_done "analyzed" "uc" "$uc_dir"; then
          phase=1; phase_name_ja="ユースケース仕様（分析）"; resolve_step "analyze"
        else
          phase=1; phase_name_ja="ユースケース仕様（レビュー通過まで）"; resolve_step "clarify"
        fi
      else
        # UC 洗い出し中は、レビュー済みでも次の UC 作成へ戻す（TDD/実装に進まない）
        if [[ $uc_discovery_completed -eq 0 ]]; then
          phase=1; phase_name_ja="ユースケース洗い出し中（次UC作成）"; resolve_step "uc_spec"
        elif [[ "$grade" == "A" ]] && [[ $has_infra_lock -eq 0 ]]; then
          phase=4; phase_name_ja="インフラ詳細設計"; resolve_step "infra_plan"
        else
          if uc_branch_has_tests_ready_for_implement; then
            phase=6; phase_name_ja="実装"; resolve_step "implement"
          else
            phase=5; phase_name_ja="テスト設計（当該 UC の spec 必須）"; resolve_step "test_design"
          fi
        fi
      fi
    fi
  else
    if [[ $on_other_work_branch -eq 1 ]]; then
      phase=1; phase_name_ja="その他作業（CI/CD・インフラ等）"; resolve_step "other_work"
    elif [[ $has_domain_lock -eq 0 ]]; then
      phase=1; phase_name_ja="ユースケース開始（仕様策定）"; resolve_step "uc_spec"
    elif [[ $has_arch_lock -eq 0 ]]; then
      phase=3; phase_name_ja="アーキテクチャ選択"; resolve_step "architecture_plan"
    else
      phase=1; phase_name_ja="ユースケース開始（仕様策定）"; resolve_step "uc_spec"
    fi
  fi

  if [[ "$JSON_MODE" == true ]]; then
    jq -cn --argjson phase "$phase" --arg name "$phase_name_ja" --arg step_id "$step_id" --arg cmd "$command" --arg file "$command_file" --arg grade "$grade" \
      --arg check "$check_command" --argjson cmds "$step_commands" \
      --arg feature_dir "$feature_dir" --arg feature_spec "$feature_spec" \
      '{phase:$phase, phase_name_ja:$name, step_id:$step_id, command:$cmd, command_file:$file, grade:$grade, check_command:$check, step_commands:$cmds, feature_dir:$feature_dir, feature_spec:$feature_spec}'
  else
    echo "現在フェーズ: Phase $phase（$phase_name_ja）"
    echo "推奨コマンド: $command"
    echo "コマンドファイル: $command_file"
    echo "グレード: $grade"
    echo "チェック（毎回）: $check_command"
    if [[ $on_uc_branch -eq 0 ]] && [[ -n "$branch" ]]; then
      echo ""
      echo "注意: main 等のままの修正は危険です。UC 用ブランチを作成してから作業してください（仕様策定ステップでブランチ作成）。"
    fi
  fi
}

# === 状態表示（lock 一覧）===
run_status() {
  echo "=== spec-runner フェーズ状況 ==="
  echo "グレード: $grade"
  echo ""
  echo "Lock（.spec-runner/phase-locks.json）:"
  for sec in charter domain architecture infra uc_discovery test_design; do
    if jq -e --arg s "$sec" '.[$s].completed == true' "$LOCK_FILE" >/dev/null 2>&1; then
      echo "  ✓ $sec"
    else
      echo "  - $sec"
    fi
  done
}

# === グレード判定チェックリスト ===
run_grade() {
  echo "=== spec-runner グレード判定 ==="
  echo ""
  echo "STEP 1: 作業の種別を判定する"
  echo "  → 既存UCの修正・バグfix: Grade C 確定（以降の判定不要）"
  echo "  → 新規UC: STEP 2 へ"
  echo ""
  echo "STEP 2: Grade B 仮置きで UC 草稿を作成する"
  echo "  → AI と対話して UC 仕様書の草稿を作成する"
  echo "  → この時点ではまだブランチ作成・コミット不要"
  echo ""
  echo "STEP 3: UC 草稿を見て Grade を確定する"
  echo "  以下のいずれかが草稿に含まれていれば Grade A:"
  echo "  □ 新しいDB・テーブル・コレクションの追加が必要"
  echo "  □ 外部API・SaaS との新規連携が必要"
  echo "  □ 新規クラウドサービスの追加が必要（S3バケット・Redisクラスタ等）"
  echo "  □ ネットワーク構成の変更が必要"
  echo "  □ CI/CDパイプラインの変更が必要"
  echo "  → 一つでも該当: Grade A 確定 → ブランチ作成 → Phase 3（UC仕様書）へ"
  echo "  → 全て非該当:  Grade B 確定 → ブランチ作成 → Phase 3（UC仕様書）へ（草稿を流用）"
  echo ""
  echo "判定結果は .spec-runner/grade-history.json に記録する（ブランチ名には含めない）。"
  echo "迷ったら上位グレードを選ぶ。"
  echo ""
  echo "現在の記録: current_grade = $grade"
}

# === 実行 ===
if [[ "$MODE" == "gate" ]]; then
  echo "=== ゲート確認（グレード: ${GATE_GRADE:-$grade}） ==="
  run_gate
elif [[ "$MODE" == "status" ]]; then
  run_status
elif [[ "$MODE" == "grade" ]]; then
  run_grade
else
  run_phase
fi
