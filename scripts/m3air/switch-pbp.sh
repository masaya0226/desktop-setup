#!/bin/bash
# Key3: PBP切替（トグル） - M3 Air 用
# サブモニタ（左）の PBPオン/オフを切り替える

# === watchdog との相互排他ロック ===
LOCK=/tmp/desktop-switcher.lock
cleanup() { sleep 2; rm -f "$LOCK"; }
trap cleanup EXIT
: > "$LOCK"

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === ディスプレイ識別 (UUID は動的解決 / 詳細は switch-main.sh のコメント参照) ===
MAIN_SERIAL="GAS00262019"; MAIN_MODEL="32908"   # メインモニタ (右)
SUB_SERIAL="E1T00045019";  SUB_MODEL="32907"    # サブモニタ (左, PBP)

MAIN_UUID=""
SUB_UUID=""

# === 入力値定数 ===
MAIN_AIR=21
MAIN_MAX=17
SUB_AIR=21
SUB_MAX=15

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_AIR

# === 通知 ===
notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Switcher\"" 2>/dev/null || true
}

# === BD host alive ===
bd_host_alive() { pgrep -x BetterDisplay >/dev/null; }

# === UUID 動的解決 ===
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

# PBP 切替は同一モニタの UUID が変わりうるため、空読み時は引き直して再挑戦する。
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
    [ -z "$got" ] && resolve_display_uuids
  done
  if [ -z "$got" ]; then
    return 0
  fi
  printf 'sub_set_verified mismatch: vcp=%s value=%s got=%s\n' "$vcp" "$value" "$got" >&2
  return 1
}

# === メインモニタ DDC 読み取り ===
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

# === main connected=on を確実に ===
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

# === 主ディスプレイ設定 ===
set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

# =============================================================
# === 本体処理 ===
# =============================================================

# --- preflight ---
if ! bd_host_alive; then
  notify "BetterDisplay 本体未起動。中断しました。"
  exit 1
fi

if ! resolve_display_uuids; then
  notify "ディスプレイ識別失敗。scripts/resolve-displays.sh で確認してください。"
  exit 1
fi

# --- main connected が off/空なら復旧 ---
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
if [ "$main_connected" != "on" ]; then
  main_ensure_connected_on || true
fi

# --- メインPC 判定 + PBP 状態取得 (別 DDC バスなので並列実行) ---
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

is_self_main=0
if [ "$current_main" = "$MY_MAIN_INPUT" ]; then
  is_self_main=1
fi

# サブモニタ入力値を決定 (current_main 信頼)
if [ "$current_main" = "$MAIN_AIR" ]; then
  SUB_MAIN_PC=$SUB_AIR
  SUB_OTHER_PC=$SUB_MAX
else
  SUB_MAIN_PC=$SUB_MAX
  SUB_OTHER_PC=$SUB_AIR
fi

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ
  # 先に 0x60=メインPC にして [main|main] 状態にしてから PBP off (他PC瞬間露出防止)
  sub_set_verified 0x60 $SUB_MAIN_PC
  sub_set_verified 0x7D 0
  new_pbp=0
  NOTIFY="PBP オフ"
else
  # PBP オフ → オン
  # switch-main は PBP off 時に 0x7E を書けないため、ここで 0x7E=メインPC を書き直す
  sub_set_verified 0x7D 2
  sub_set_verified 0x7E $SUB_MAIN_PC
  sub_set_verified 0x60 $SUB_OTHER_PC
  new_pbp=2
  NOTIFY="PBP オン"
fi

# --- connected 管理 ---
# self がメイン: 常に on を保証
# self が非メイン:
#   new_pbp=2 → 自分はサブ左に映るので幽霊スペース防止のため off
#   new_pbp=0 → 自分はどこにも映らないので触らない (Spaces 再配置回避)
if [ "$is_self_main" = "1" ]; then
  main_ensure_connected_on || true
  sleep 1
  set_main_display
else
  if [ "$new_pbp" = "2" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
  fi
fi

notify "$NOTIFY"
