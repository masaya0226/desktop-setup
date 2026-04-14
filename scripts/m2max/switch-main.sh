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

# === UUID (M2 Max から見た値) ===
MAIN_UUID="7A782274-C5F3-414C-B90A-41770749B121"
SUB_UUID_OFF="4A8F5105-1777-4D51-8E49-ECDD133C3D7B"
SUB_UUID_ON="C2E62FA2-0938-463E-92B2-FD77960B47C5"

# === 入力値定数 ===
MAIN_AIR=21   # TB
MAIN_MAX=17   # HDMI
SUB_AIR=21    # TB
SUB_MAX=15    # DP

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_MAX
MY_SUB_INPUT=$SUB_MAX

notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Switcher\"" 2>/dev/null || true
}

bd_host_alive() { pgrep -x BetterDisplay >/dev/null; }

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

set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

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
  if bd_recover_if_lost "$MAIN_UUID"; then
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
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ -z "$current_main" ]; then
  notify "メインモニタ DDC 読み取り失敗。中断しました。"
  exit 1
fi

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

if ! main_set_input_verified $TARGET_MAIN; then
  notify "メインモニタ切替失敗。中断しました。"
  exit 1
fi

if [ "$current_pbp" = "2" ]; then
  sleep 1
  sub_set_verified 0x7E $TARGET_SUB_MAIN
  sub_set_verified 0x60 $TARGET_SUB_OTHER
else
  sleep 1
  sub_set_verified 0x60 $TARGET_SUB_MAIN
fi

if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  main_ensure_connected_on || true
  sleep 1
  set_main_display
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

notify "$NOTIFY"
