#!/usr/bin/env bash
# spec-runner 判定の単一入口。振る舞い仕様に沿って「フェーズ・ゲート・状態・グレード」を扱う。
# 使用: spec-runner-core.sh [--phase] [--json] | --gate [GRADE] | --status | --grade
# cmd-dispatch.sh（次のステップ・ゲート確認・ブランチ作成）から呼ばれる。

set -e
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || echo ".")}"
cd "$REPO_ROOT"
STEPS_DIR="${STEPS_DIR:-$REPO_ROOT/.spec-runner/steps}"
LOCK_FILE=".spec-runner/phase-locks.json"
PROJECT_JSON=".spec-runner/project.json"

MODE="phase"
JSON_MODE=false
GATE_GRADE=""
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

# === 共通: lock / grade / branch を一度だけ読む ===
has_charter_lock=0
has_domain_lock=0
has_arch_lock=0
has_infra_lock=0
if [[ -f "$LOCK_FILE" ]] && command -v jq >/dev/null 2>&1; then
  [[ "$(jq -r '.charter.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] && has_charter_lock=1
  [[ "$(jq -r '.domain.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] && has_domain_lock=1
  [[ "$(jq -r '.architecture.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] && has_arch_lock=1
  [[ "$(jq -r '.infra.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] && has_infra_lock=1
fi

grade="LOOP1"
if [[ -f ".spec-runner/grade-history.json" ]] && command -v jq >/dev/null 2>&1; then
  grade=$(jq -r '.current_grade // "LOOP1"' .spec-runner/grade-history.json 2>/dev/null || echo "LOOP1")
fi

branch=$(git branch --show-current 2>/dev/null || echo "")
branch_prefix="feature"
test_dir="tests"
test_pattern="*.spec.*"
if [[ -f "$PROJECT_JSON" ]] && command -v jq >/dev/null 2>&1; then
  p=$(jq -r '.naming.branch_prefix // empty' "$PROJECT_JSON" 2>/dev/null)
  [[ -n "$p" ]] && branch_prefix="$p"
  d=$(jq -r '.test_design.dir // empty' "$PROJECT_JSON" 2>/dev/null)
  [[ -n "$d" ]] && test_dir="$d"
  pat=$(jq -r '.test_design.pattern // empty' "$PROJECT_JSON" 2>/dev/null)
  [[ -n "$pat" ]] && test_pattern="$pat"
fi
on_uc_branch=0
on_other_work_branch=0
current_uc_id=""
other_work_pattern="work|infra|cicd"
if [[ -f "$PROJECT_JSON" ]] && command -v jq >/dev/null 2>&1; then
  ow=$(jq -r '.naming.other_work_prefixes[]? // empty' "$PROJECT_JSON" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
  [[ -n "$ow" ]] && other_work_pattern="$ow"
fi
if [[ "$branch" =~ ^${branch_prefix}/UC-[0-9]{3}- ]]; then
  on_uc_branch=1
  current_uc_id="${branch#*/}"
elif [[ "$branch" =~ ^${branch_prefix}/(${other_work_pattern})/ ]]; then
  on_other_work_branch=1
fi

# === ゲート確認モード ===
run_gate() {
  exit_error() { echo "GATE: $1" >&2; exit 1; }
  GRD="${GATE_GRADE:-$grade}"
  [[ -f "$LOCK_FILE" ]] || exit_error "phase-locks.json が存在しません"
  command -v jq >/dev/null 2>&1 || exit_error "jq がインストールされていません（例: brew install jq）"

  check_required_paths() {
    local key="$1"
    local list
    if [[ -f "$PROJECT_JSON" ]]; then
      list=$(jq -r --arg k "$key" '.required_docs[$k][]? // empty' "$PROJECT_JSON" 2>/dev/null)
    fi
    if [[ -z "$list" ]]; then return 1; fi
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ -f "$path" ]]; then
        :
      elif [[ -d "$path" ]]; then
        count=$(find "$path" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
        [[ "${count:-0}" -ge 1 ]] || exit_error "必須: $path に 1 件以上の .md がありません"
      else
        exit_error "必須: $path が存在しません"
      fi
    done <<< "$list"
    return 0
  }

  if check_required_paths "charter"; then :; else
    [[ -f "docs/01_憲章/憲章.md" ]] || exit_error "憲章.md が存在しません"
  fi
  if [[ "$GRD" == "LOOP1" ]]; then
    [[ "$(jq -r '.charter.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] || exit_error "Phase 0 未完了（phase-locks.json の charter.completed）"
    jq -e '.charter.reviewed_by' "$LOCK_FILE" >/dev/null 2>&1 || exit_error "憲章に署名がありません（charter.reviewed_by）"
    echo "Phase 0: OK"
  fi
  if [[ "$GRD" != "LOOP1" ]]; then
    [[ "$(jq -r '.domain.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] || exit_error "Phase 1 未完了"
    if check_required_paths "domain"; then :; else
      for doc in ユビキタス言語辞書 ドメインモデル 集約; do
        [[ -f "docs/03_ドメイン設計/${doc}.md" ]] || exit_error "${doc}.md が存在しません"
      done
    fi
    echo "Phase 1: OK"
    [[ "$(jq -r '.architecture.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] || exit_error "Phase 2 未完了"
    if check_required_paths "architecture"; then :; else
      [[ -f "docs/04_アーキテクチャ/パターン選定.md" ]] || exit_error "パターン選定.md が存在しません"
      [[ -f "docs/04_アーキテクチャ/インフラ方針.md" ]] || exit_error "インフラ方針.md が存在しません"
      [[ $(find "docs/04_アーキテクチャ/設計判断記録/" -name "*.md" 2>/dev/null | wc -l) -gt 0 ]] || exit_error "ADR が 1 件もありません"
    fi
    echo "Phase 2: OK"
  fi
  if [[ "$GRD" == "A" ]]; then
    [[ "$(jq -r '.infra.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] || exit_error "Grade A: インフラ設計未完了"
    if check_required_paths "grade_a"; then :; else
      [[ -f "docs/05_インフラ設計/schema.dbml" ]] || exit_error "Grade A 必須: docs/05_インフラ設計/schema.dbml が存在しません"
    fi
    echo "Phase 4 (Grade A): OK"
  fi
  if [[ "$GRD" == "A" || "$GRD" == "B" ]]; then
    uc_count=$(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -name "UC-*.md" 2>/dev/null | wc -l)
    if [[ "${uc_count:-0}" -gt 0 ]]; then
      uc_reviewed_count=$(jq -r '.uc_reviewed // [] | length' "$LOCK_FILE" 2>/dev/null || echo 0)
      [[ "${uc_reviewed_count:-0}" -gt 0 ]] || exit_error "Gate 3: uc_reviewed に少なくとも1件の UC 識別子を登録してください"
      if check_required_paths "gate3_openapi"; then :; else
        [[ -f "docs/06_API仕様/openapi.yaml" ]] || exit_error "Gate 3: docs/06_API仕様/openapi.yaml が存在しません"
      fi
      echo "Gate 3 (UC+OpenAPI): OK"
    fi
    test_design_ok=0
    [[ "$(jq -r '.test_design.completed // false' "$LOCK_FILE" 2>/dev/null)" == "true" ]] && test_design_ok=1
    if [[ $test_design_ok -eq 1 ]] || [[ -d "$test_dir" && -n "$(find "$test_dir" -type f -name "$test_pattern" 2>/dev/null | head -1)" ]]; then
      echo "Gate 5 (テスト設計): OK"
    fi
  fi
  if [[ "$GRD" == "A" || "$GRD" == "B" || "$GRD" == "C" ]]; then
    if [[ -f ".spec-runner/scripts/test/require-tests-green.sh" ]]; then
      .spec-runner/scripts/test/require-tests-green.sh 2>/dev/null && echo "Gate 6 (テスト通過): OK" || true
    elif [[ -f "docker-compose.yml" ]] || [[ -f "compose.yml" ]]; then
      docker compose run --rm app npm test 2>/dev/null && echo "Gate 6 (テスト通過): OK" || true
    elif [[ -f "package.json" ]]; then
      npm test 2>/dev/null && echo "Gate 6 (テスト通過): OK" || true
    fi
  fi
  echo "ゲート確認: 通過"
}

# === フェーズ判定モード ===
run_phase() {
  phase=0
  phase_name_ja=""
  command=""
  command_file=""

  # UC → ドメイン → アーキ の順で進める
  uc_count_total=$(find docs/02_ユースケース仕様 -mindepth 2 -maxdepth 2 -name "UC-*.md" 2>/dev/null | wc -l | tr -d ' ')
  uc_count_total=${uc_count_total:-0}

  if [[ $has_charter_lock -eq 0 ]]; then
    phase=0; phase_name_ja="憲章策定"; command="憲章"; command_file="$STEPS_DIR/憲章.md"
  elif [[ $has_domain_lock -eq 0 && ${uc_count_total} -gt 0 && $on_uc_branch -eq 0 ]]; then
    # UC が少なくとも 1 本できたら、そこからドメインを固める
    phase=2; phase_name_ja="ドメイン設計"; command="ドメイン設計"; command_file="$STEPS_DIR/ドメイン設計.md"
  elif [[ $has_arch_lock -eq 0 && $has_domain_lock -eq 1 ]]; then
    phase=3; phase_name_ja="アーキテクチャ選択"; command="実装計画"; command_file="$STEPS_DIR/実装計画.md"
  elif [[ $on_uc_branch -eq 1 ]]; then
    uc_spec=""
    if [[ -n "$current_uc_id" ]]; then
      for f in docs/02_ユースケース仕様/*/"${current_uc_id}.md"; do [[ -f "$f" ]] && uc_spec="$f" && break; done
    fi
    if [[ -z "$uc_spec" ]]; then
      phase=1; phase_name_ja="ユースケース仕様"; command="仕様策定"; command_file="$STEPS_DIR/仕様策定.md"
    else
      uc_dir=$(basename "$uc_spec" .md)
      reviewed=0
      [[ -f "$LOCK_FILE" ]] && command -v jq >/dev/null 2>&1 && jq -e --arg u "$uc_dir" '.uc_reviewed[]? == $u' "$LOCK_FILE" 2>/dev/null | grep -q true && reviewed=1
      if [[ $reviewed -eq 0 ]]; then
        phase=1; phase_name_ja="ユースケース仕様（レビュー通過まで）"; command="曖昧さ解消"; command_file="$STEPS_DIR/曖昧さ解消.md"
      else
        if [[ "$grade" == "A" ]] && [[ $has_infra_lock -eq 0 ]]; then
          phase=4; phase_name_ja="インフラ詳細設計"; command="実装計画"; command_file="$STEPS_DIR/実装計画.md"
        else
          has_tests=0
          [[ -d "$test_dir" ]] && [[ -n "$(find "$test_dir" -type f -name "$test_pattern" 2>/dev/null | head -1)" ]] && has_tests=1
          if [[ $has_tests -eq 0 ]]; then
            phase=5; phase_name_ja="テスト設計"; command="テスト設計"; command_file="$STEPS_DIR/テスト設計.md"
          else
            phase=6; phase_name_ja="実装"; command="実装"; command_file="$STEPS_DIR/実装.md"
          fi
        fi
      fi
    fi
  else
    if [[ $on_other_work_branch -eq 1 ]]; then
      phase=1; phase_name_ja="その他作業（CI/CD・インフラ等）"; command="その他作業"; command_file="$STEPS_DIR/その他作業.md"
    elif [[ $has_domain_lock -eq 0 ]]; then
      # まだ UC が無い場合は UC から始める
      phase=1; phase_name_ja="ユースケース開始（仕様策定）"; command="仕様策定"; command_file="$STEPS_DIR/仕様策定.md"
    elif [[ $has_arch_lock -eq 0 ]]; then
      phase=3; phase_name_ja="アーキテクチャ選択"; command="実装計画"; command_file="$STEPS_DIR/実装計画.md"
    else
      phase=1; phase_name_ja="ユースケース開始（仕様策定）"; command="仕様策定"; command_file="$STEPS_DIR/仕様策定.md"
    fi
  fi

  if [[ "$JSON_MODE" == true ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq -cn --argjson phase $phase --arg name "$phase_name_ja" --arg cmd "$command" --arg file "$command_file" --arg grade "$grade" \
        '{phase:$phase, phase_name_ja:$name, command:$cmd, command_file:$file, grade:$grade}'
    else
      echo "{\"phase\":$phase,\"phase_name_ja\":\"$phase_name_ja\",\"command\":\"$command\",\"command_file\":\"$command_file\",\"grade\":\"$grade\"}"
    fi
  else
    echo "現在フェーズ: Phase $phase（$phase_name_ja）"
    echo "推奨コマンド: $command"
    echo "コマンドファイル: $command_file"
    echo "グレード: $grade"
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
  if [[ -f "$LOCK_FILE" ]] && command -v jq >/dev/null 2>&1; then
    for sec in charter domain architecture infra test_design; do
      val=$(jq -r --arg s "$sec" '.[$s].completed // false' "$LOCK_FILE" 2>/dev/null)
      [[ "$val" == "true" ]] && echo "  ✓ $sec" || echo "  - $sec"
    done
  else
    echo "  phase-locks.json が存在しないか jq がインストールされていません"
  fi
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
