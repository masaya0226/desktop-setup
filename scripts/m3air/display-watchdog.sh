#!/bin/bash
# Display Watchdog: サブモニタの状態を見てメインモニタの connected を管理 - M3 Air 用
# サブモニタは常に connected=on なので DDC 読み取り可能。
# 切替スクリプトがカバーしきれないケース（PBP切替後など）の補完。

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M3 Air から見た値) ===
MAIN_UUID="2DF75969-A2F5-4608-A9B4-429B3A3CA4BB"
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# === 自分のサブモニタ入力値 ===
MY_SUB_INPUT=21   # M3 Air は TB

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

# === 切替スクリプトとの相互排他ロック ===
# Key2/Key3 実行中は DDC read や connected write を行わない。
# 30 秒以上古いロックは stale とみなして削除する (trap 失敗時の保険)。
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
    # PBPオン時:
    # Sub 0x60=自分 → 自分はサブ左 (メインは他PC) → off
    # Sub 0x60=他PC → 自分がメイン → on
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      should_be="off"
    else
      should_be="on"
    fi
  else
    # PBPオフ時:
    # Sub 0x60=自分 → 自分が active PC → on (connected=off 残留の補完が必要)
    # Sub 0x60≠自分 → 自分は不可視。connected の状態はユーザ体験に影響しないので
    #                 触らない (Spaces 再配置を避けるため)
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      should_be="on"
    fi
  fi

  if [ -n "$should_be" ] && [ "$current_connected" != "$should_be" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=$should_be 2>/dev/null || true
  fi

  sleep 4
done
