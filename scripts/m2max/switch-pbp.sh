#!/bin/bash
# Key3: PBP切替（トグル） - M2 Max 用

# === watchdog との相互排他ロック ===
LOCK=/tmp/desktop-switcher.lock
cleanup() { sleep 2; rm -f "$LOCK"; }
trap cleanup EXIT
: > "$LOCK"

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M2 Max から見た値) ===
MAIN_UUID="7A782274-C5F3-414C-B90A-41770749B121"
SUB_UUID_OFF="4A8F5105-1777-4D51-8E49-ECDD133C3D7B"
SUB_UUID_ON="C2E62FA2-0938-463E-92B2-FD77960B47C5"

# === 入力値定数 ===
MAIN_AIR=21   # TB
MAIN_MAX=17   # HDMI
SUB_AIR=21    # TB
SUB_MAX=15    # DP

# === 自分のメインモニタ入力値 ===
MY_MAIN_INPUT=$MAIN_MAX   # M2 Max は HDMI

# === サブモニタ DDC ヘルパー (PBP状態でUUIDが変わるため両方試行) ===
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
  done
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

# === メインPC判定 (メインモニタの 0x60 から) ===
current_main=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
is_self_main=0
if [ "$current_main" = "$MY_MAIN_INPUT" ]; then
  is_self_main=1
fi

if [ "$current_main" = "$MAIN_AIR" ]; then
  SUB_MAIN_PC=$SUB_AIR
  SUB_OTHER_PC=$SUB_MAX
else
  SUB_MAIN_PC=$SUB_MAX
  SUB_OTHER_PC=$SUB_AIR
fi

current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ: 先に 0x60=メインPC にしてから PBP off
  sub_set_verified 0x60 $SUB_MAIN_PC
  sub_set_verified 0x7D 0
  NEW_PBP=0
  osascript -e 'display notification "PBP オフ" with title "Desktop Switcher"'
else
  # PBP オフ → オン
  # switch-main.sh は PBP off 時に 0x7E を書けないため、ここで 0x7E=メインPC
  # を明示的に書き直す (silent drop 対策は sub_set_verified が担う)。
  sub_set_verified 0x7D 2
  sub_set_verified 0x7E $SUB_MAIN_PC
  sub_set_verified 0x60 $SUB_OTHER_PC
  NEW_PBP=2
  osascript -e 'display notification "PBP オン" with title "Desktop Switcher"'
fi

# === PBP切替後にメインモニタを主ディスプレイに復帰 (自分がメインの場合のみ) ===
if [ "$is_self_main" = "1" ]; then
  sleep 1
  set_main_display
fi
