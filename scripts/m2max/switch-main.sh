#!/bin/bash
# Key2: メイン入替（トグル） - M2 Max 用
# 構成: [Sub(左,PBP)] [Main(右)]
# PBP時: Sub左(0x60)=他PC, Sub右(0x7E)=メインPC

# === watchdog との相互排他ロック ===
LOCK=/tmp/desktop-switcher.lock
cleanup() { sleep 2; rm -f "$LOCK"; }
trap cleanup EXIT
: > "$LOCK"

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === ディスプレイ識別 (UUID は動的解決) ===
# BD の UUID はハードコード禁止。TB/DP の再列挙で portID が変わると BD が
# 同一個体に別 UUID を採番するため (2026-08 に実際に発生し全切替が停止した)。
# 個体固有の EDID シリアルから毎回引き直す。EDID が読めず Generic Display に
# 落ちた場合に備えて model 番号を第二キーにする。
MAIN_SERIAL="GAS00262019"; MAIN_MODEL="32908"   # メインモニタ (右)
SUB_SERIAL="E1T00045019";  SUB_MODEL="32907"    # サブモニタ (左, PBP)

MAIN_UUID=""
SUB_UUID=""

# === 入力値定数 ===
MAIN_AIR=21   # TB
MAIN_MAX=17   # HDMI
SUB_AIR=21    # TB
SUB_MAX=15    # DP

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_MAX
MY_SUB_INPUT=$SUB_MAX

# === 通知 ===
notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Switcher\"" 2>/dev/null || true
}

# === BD host (GUI 本体) が動いているか ===
bd_host_alive() {
  pgrep -x BetterDisplay >/dev/null
}

# === UUID 動的解決 ===
# `$BD get -identifiers` の出力から、指定フィールドが一致する
# エントリの UUID を返す。UUID は各オブジェクトの先頭キー。
bd_uuid_by_field() {
  local field=$1 want=$2 uuid="" line val
  while IFS= read -r line; do
    case "$line" in
      '{'|'},{') uuid="" ;;
    esac
    case "$line" in
      *'"UUID"'*)
        val=${line#*: \"}; uuid=${val%\"*} ;;
      *"\"$field\""*)
        val=${line#*: \"}; val=${val%\"*}
        if [ "$val" = "$want" ] && [ -n "$uuid" ]; then
          printf '%s\n' "$uuid"
          return 0
        fi ;;
    esac
  done < <($BD get -identifiers 2>/dev/null)
  return 1
}

# MAIN_UUID / SUB_UUID を引き直す。両方取れて別物なら成功。
# 旧実装の `perform -reconfigure` による復旧はここで置き換わる
# (reconfigure は BD host を不安定にするため呼ばない)。
resolve_display_uuids() {
  MAIN_UUID=$(bd_uuid_by_field alphanumericSerial "$MAIN_SERIAL") \
    || MAIN_UUID=$(bd_uuid_by_field model "$MAIN_MODEL") \
    || MAIN_UUID=""
  SUB_UUID=$(bd_uuid_by_field alphanumericSerial "$SUB_SERIAL") \
    || SUB_UUID=$(bd_uuid_by_field model "$SUB_MODEL") \
    || SUB_UUID=""
  [ -n "$MAIN_UUID" ] && [ -n "$SUB_UUID" ] && [ "$MAIN_UUID" != "$SUB_UUID" ]
}

# === サブモニタ DDC ヘルパー ===
# 書き込み直後は DDC バスが数秒不安定で空読み・値ズレが起きる (実測)。
# 旧実装は 2 つの UUID を順に試すことで実質リトライになっていたため、
# 単一 UUID 化にあたって明示的なリトライを入れる。
sub_get() {
  local vcp=$1 val
  for _ in 1 2 3; do
    val=$($BD get -uuid="$SUB_UUID" -ddc -vcp=$vcp 2>/dev/null || echo "")
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
    sleep 1
  done
  echo ""
  return 1
}

sub_set() {
  $BD set -uuid="$SUB_UUID" -ddc -vcp=$1 -value=$2 2>/dev/null || true
}

# PBP off 時の 0x7E 書き込みは BenQ が silent drop するため、
# 書き込み後に読み戻して一致するまで最大 3 回リトライする。
sub_set_verified() {
  local vcp=$1
  local value=$2
  local got=""
  for _ in 1 2 3; do
    sub_set $vcp $value
    sleep 1
    got=$(sub_get $vcp)
    if [ "$got" = "$value" ]; then
      return 0
    fi
    # 空読みは UUID が変わった可能性 → 引き直して再挑戦
    [ -z "$got" ] && resolve_display_uuids
  done
  # 最終 read-back が空値なら DDC 確認不能として警告抑制
  if [ -z "$got" ]; then
    return 0
  fi
  printf 'sub_set_verified mismatch: vcp=%s value=%s got=%s\n' "$vcp" "$value" "$got" >&2
  return 1
}

# === 主ディスプレイ設定 ===
set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

# === メインモニタ DDC 読み取り ===
# 空読み→リトライ、5 回失敗したら UUID を引き直して再挑戦
main_get_input() {
  local val=""
  for _ in 1 2 3 4 5; do
    val=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
    sleep 1
  done
  if resolve_display_uuids; then
    for _ in 1 2 3; do
      val=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
      if [ -n "$val" ]; then
        echo "$val"
        return 0
      fi
      sleep 1
    done
  fi
  return 1
}

# === メインモニタ DDC 書き込み ===
# "Failed." 検出でリトライ、3 回失敗したら UUID を引き直して再挑戦
main_set_input() {
  local value=$1
  local err
  for _ in 1 2 3; do
    err=$($BD set -uuid="$MAIN_UUID" -ddc -vcp=0x60 -value=$value 2>&1 >/dev/null)
    if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
      return 0
    fi
    sleep 1
  done
  if resolve_display_uuids; then
    for _ in 1 2 3; do
      err=$($BD set -uuid="$MAIN_UUID" -ddc -vcp=0x60 -value=$value 2>&1 >/dev/null)
      if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
        return 0
      fi
      sleep 1
    done
  fi
  printf 'main_set_input failed: %s\n' "$err" >&2
  return 1
}

# === 書き込み後に読み戻して一致するまでリトライ ===
main_set_input_verified() {
  local value=$1
  local got
  for _ in 1 2 3; do
    main_set_input $value
    sleep 1
    got=$(main_get_input 2>/dev/null || echo "")
    if [ "$got" = "$value" ]; then
      return 0
    fi
  done
  printf 'main_set_input_verified mismatch: value=%s got=%s\n' "$value" "$got" >&2
  return 1
}

# === main connected=on を確実に ===
# set が Failed. を返したら UUID を引き直して 1 回リトライ
main_ensure_connected_on() {
  local err
  err=$($BD set -uuid="$MAIN_UUID" -connected=on 2>&1 >/dev/null)
  if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
    sleep 1
    return 0
  fi
  if resolve_display_uuids; then
    err=$($BD set -uuid="$MAIN_UUID" -connected=on 2>&1 >/dev/null)
    if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
      sleep 1
      return 0
    fi
  fi
  return 1
}

# =============================================================
# === 本体処理 ===
# =============================================================

# --- preflight: BD host alive ---
if ! bd_host_alive; then
  notify "BetterDisplay 本体未起動。中断しました。"
  exit 1
fi

# --- preflight: UUID 解決 ---
if ! resolve_display_uuids; then
  notify "ディスプレイ識別失敗。scripts/resolve-displays.sh で確認してください。"
  exit 1
fi

# --- main connected が off または空なら on へ復旧 ---
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
if [ "$main_connected" != "on" ]; then
  main_ensure_connected_on || true
fi

# --- 現在状態取得 (メイン/サブは別 DDC バスなので並列実行) ---
TMP_MAIN_VAL=$(mktemp)
TMP_PBP_VAL=$(mktemp)
( main_get_input > "$TMP_MAIN_VAL" 2>/dev/null ) & pid_m=$!
( sub_get 0x7D    > "$TMP_PBP_VAL"  2>/dev/null ) & pid_p=$!
wait $pid_m
wait $pid_p
current_main=$(cat "$TMP_MAIN_VAL")
current_pbp=$(cat "$TMP_PBP_VAL")
rm -f "$TMP_MAIN_VAL" "$TMP_PBP_VAL"
[ -z "$current_pbp" ] && current_pbp=0

if [ -z "$current_main" ]; then
  notify "メインモニタ DDC 読み取り失敗。中断しました。"
  exit 1
fi

# --- トグル方向決定 ---
if [ "$current_main" = "$MAIN_AIR" ]; then
  TARGET_MAIN=$MAIN_MAX
  TARGET_SUB_MAIN=$SUB_MAX
  TARGET_SUB_OTHER=$SUB_AIR
  NOTIFY="M2 Max に切替"
else
  TARGET_MAIN=$MAIN_AIR
  TARGET_SUB_MAIN=$SUB_AIR
  TARGET_SUB_OTHER=$SUB_MAX
  NOTIFY="M3 Air に切替"
fi

# --- メイン+サブ DDC 書き込み (別バスなので並列実行) ---
# サブ内部 (0x7E → 0x60) は同一バスなので branch 内で順序維持。
TMP_MAIN_LOG=$(mktemp)
TMP_SUB_LOG=$(mktemp)

( main_set_input_verified $TARGET_MAIN 2>"$TMP_MAIN_LOG" ) & pid_m=$!

if [ "$current_pbp" = "2" ]; then
  ( sub_set_verified 0x7E $TARGET_SUB_MAIN  2>"$TMP_SUB_LOG" \
    && sub_set_verified 0x60 $TARGET_SUB_OTHER 2>>"$TMP_SUB_LOG" ) & pid_s=$!
else
  ( sub_set_verified 0x60 $TARGET_SUB_MAIN  2>"$TMP_SUB_LOG" ) & pid_s=$!
fi

wait $pid_m; main_rc=$?
wait $pid_s; sub_rc=$?

[ -s "$TMP_MAIN_LOG" ] && cat "$TMP_MAIN_LOG" >&2
[ -s "$TMP_SUB_LOG"  ] && cat "$TMP_SUB_LOG"  >&2
rm -f "$TMP_MAIN_LOG" "$TMP_SUB_LOG"

if [ $main_rc -ne 0 ]; then
  notify "メインモニタ切替失敗。中断しました。"
  exit 1
fi

# --- メインモニタ connected 管理 (幽霊スペース対策) ---
# 注意: switch-main は現メイン PC 側からしか実行できないため、構造上
# 常に self は「新非メイン側」になる。if ブランチは防御コード。
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  main_ensure_connected_on || true
  sleep 1
  set_main_display
else
  # 自分が新非メインになる場合
  # PBP on: 自分はサブ左に映るので幽霊スペース防止のため off
  # PBP off: 自分はどこにも映らない (connected の状態はユーザ体験に影響しない)
  #         → 触らない。Spaces 再配置コストを避ける
  if [ "$current_pbp" = "2" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
  fi
fi

notify "$NOTIFY"
