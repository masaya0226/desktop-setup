#!/bin/bash
# Key3: PBP切替（トグル） - M3 Air 用
# サブモニタ（左）の PBPオン/オフを切り替える

# === watchdog との相互排他ロック ===
LOCK=/tmp/desktop-switcher.lock
cleanup() { sleep 2; rm -f "$LOCK"; }
trap cleanup EXIT
: > "$LOCK"

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M3 Air から見た値) ===
MAIN_UUID="2DF75969-A2F5-4608-A9B4-429B3A3CA4BB"
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

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

# === BD リカバリ (UUID が消えている場合のみ reconfigure を呼ぶ) ===
bd_is_uuid_tracked() {
  local uuid=$1
  $BD get -identifiers 2>/dev/null | grep -q "\"UUID\" : \"$uuid\""
}

bd_recover_if_lost() {
  local uuid=$1
  if bd_is_uuid_tracked "$uuid"; then
    return 0
  fi
  $BD perform -reconfigure >/dev/null 2>&1 || true
  sleep 2
  bd_is_uuid_tracked "$uuid"
}

# === サブモニタ DDC ヘルパー ===
sub_get() {
  local vcp=$1
  local val
  val=$($BD get -uuid="$SUB_UUID_OFF" -ddc -vcp=$vcp 2>/dev/null || echo "")
  if [ -z "$val" ]; then
    val=$($BD get -uuid="$SUB_UUID_ON" -ddc -vcp=$vcp 2>/dev/null || echo "")
  fi
  echo "$val"
}

sub_set() {
  local vcp=$1
  local value=$2
  if ! $BD set -uuid="$SUB_UUID_OFF" -ddc -vcp=$vcp -value=$value 2>/dev/null; then
    $BD set -uuid="$SUB_UUID_ON" -ddc -vcp=$vcp -value=$value 2>/dev/null || true
  fi
}

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
  if bd_recover_if_lost "$MAIN_UUID"; then
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
  if bd_recover_if_lost "$MAIN_UUID"; then
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

# --- main connected が off/空なら復旧 ---
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
if [ "$main_connected" != "on" ]; then
  main_ensure_connected_on || true
fi

# --- メインPC 判定 ---
current_main=$(main_get_input || echo "")
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

# --- 現在の PBP 状態を取得 ---
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ
  # 先に 0x60=メインPC にして [main|main] 状態にしてから PBP off (他PC瞬間露出防止)
  sub_set_verified 0x60 $SUB_MAIN_PC
  sub_set_verified 0x7D 0
  NOTIFY="PBP オフ"
else
  # PBP オフ → オン
  # switch-main は PBP off 時に 0x7E を書けないため、ここで 0x7E=メインPC を書き直す
  sub_set_verified 0x7D 2
  sub_set_verified 0x7E $SUB_MAIN_PC
  sub_set_verified 0x60 $SUB_OTHER_PC
  NOTIFY="PBP オン"
fi

# --- connected 管理 (自分がメインなら on、そうでなければ off を idempotent に) ---
if [ "$is_self_main" = "1" ]; then
  main_ensure_connected_on || true
  sleep 1
  set_main_display
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

notify "$NOTIFY"
