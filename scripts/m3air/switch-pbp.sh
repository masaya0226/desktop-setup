#!/bin/bash
# Key3: PBP切替（トグル） - M3 Air 用
# サブモニタ（左）の PBPオン/オフを切り替える
# 入力設定(0x60, 0x7E)はPBP切替で維持されるため触らない

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M3 Air から見た値) ===
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

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

# === 現在の PBP 状態を取得 ===
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ
  sub_set 0x7D 0
  osascript -e 'display notification "PBP オフ" with title "Desktop Switcher"'
else
  # PBP オフ → オン
  sub_set 0x7D 2
  # PBPオン後: connected 管理は watchdog に任せる
  osascript -e 'display notification "PBP オン" with title "Desktop Switcher"'
fi
