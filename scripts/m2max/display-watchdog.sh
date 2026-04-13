#!/bin/bash
# Display Watchdog - M2 Max 用

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M2 Max から見た値) ===
MAIN_UUID="7A782274-C5F3-414C-B90A-41770749B121"
SUB_UUID_OFF="4A8F5105-1777-4D51-8E49-ECDD133C3D7B"
SUB_UUID_ON="C2E62FA2-0938-463E-92B2-FD77960B47C5"

# === 自分のサブモニタ入力値 ===
MY_SUB_INPUT=15   # M2 Max は DP

sub_get() {
  local vcp=$1
  local val
  val=$($BD get -uuid="$SUB_UUID_OFF" -ddc -vcp=$vcp 2>/dev/null || echo "")
  if [ -z "$val" ]; then
    val=$($BD get -uuid="$SUB_UUID_ON" -ddc -vcp=$vcp 2>/dev/null || echo "")
  fi
  echo "$val"
}

# === 切替スクリプトとの相互排他ロック ===
LOCK=/tmp/desktop-switcher.lock

while true; do
  if [ -e "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 30 ]; then
      rm -f "$LOCK"
    else
      sleep 2
      continue
    fi
  fi

  pbp=$(sub_get 0x7D)
  sub_main=$(sub_get 0x60)

  if [ -z "$pbp" ] || [ -z "$sub_main" ]; then
    sleep 4
    continue
  fi

  current_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
  should_be=""

  if [ "$pbp" = "2" ]; then
    # PBPオン: Sub 0x60=自分 → サブ左=自分 → main は他PC → off
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      should_be="off"
    else
      should_be="on"
    fi
  else
    # PBPオフ: Sub 0x60=自分 → 自分が active PC → main=on
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      should_be="on"
    else
      should_be="off"
    fi
  fi

  if [ "$current_connected" != "$should_be" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=$should_be 2>/dev/null || true
  fi

  sleep 4
done
