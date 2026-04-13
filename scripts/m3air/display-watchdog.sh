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

while true; do
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
    # Sub左(0x60)=自分 → 自分がサブ側 → メインモニタは他PCを表示中 → off
    # Sub左(0x60)=他PC → 自分がメイン → メインモニタは自分を表示中 → on
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      should_be="off"
    else
      should_be="on"
    fi
  else
    # PBPオフ: メインモニタは触らない
    sleep 4
    continue
  fi

  if [ "$current_connected" != "$should_be" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=$should_be 2>/dev/null || true
  fi

  sleep 4
done
