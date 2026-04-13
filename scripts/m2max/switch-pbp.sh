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
MAIN_AIR=21
MAIN_MAX=17
SUB_AIR=21
SUB_MAX=15

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_MAX   # M2 Max は HDMI

notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Switcher\"" 2>/dev/null || true
}

bd_host_alive() { pgrep -x BetterDisplay >/dev/null; }

bd_recover() {
  $BD perform -reconfigure >/dev/null 2>&1 || true
  sleep 2
}

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

main_get_input() {
  local val=""
  local pass
  for pass in 1 2; do
    for _ in 1 2 3 4 5; do
      val=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
      if [ -n "$val" ]; then
        echo "$val"
        return 0
      fi
      sleep 1
    done
    [ "$pass" = "1" ] && bd_recover
  done
  return 1
}

main_ensure_connected_on() {
  local err try
  for try in 1 2 3; do
    err=$($BD set -uuid="$MAIN_UUID" -connected=on 2>&1 >/dev/null)
    if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
      sleep 1
      return 0
    fi
    bd_recover
  done
  return 1
}

set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

# =============================================================
# === 本体処理 ===
# =============================================================

if ! bd_host_alive; then
  notify "BetterDisplay 本体未起動。中断しました。"
  exit 1
fi

main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
if [ "$main_connected" != "on" ]; then
  main_ensure_connected_on || true
fi

current_main=$(main_get_input || echo "")
if [ -z "$current_main" ]; then
  notify "メインモニタ DDC 読み取り失敗。中断しました。"
  exit 1
fi

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
  sub_set_verified 0x60 $SUB_MAIN_PC
  sub_set_verified 0x7D 0
  NOTIFY="PBP オフ"
else
  sub_set_verified 0x7D 2
  sub_set_verified 0x7E $SUB_MAIN_PC
  sub_set_verified 0x60 $SUB_OTHER_PC
  NOTIFY="PBP オン"
fi

if [ "$is_self_main" = "1" ]; then
  main_ensure_connected_on || true
  sleep 1
  set_main_display
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

notify "$NOTIFY"
