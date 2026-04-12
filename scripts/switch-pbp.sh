#!/bin/bash
# Key3: PBP切替（トグル）
# サブモニタ（左）の PBPオン/オフを切り替える
# 入力設定(0x60, 0x7E)はPBP切替で維持されるため触らない
#
# M3 Air 用。M2 Max 用は MY_MAIN_INPUT を変更する。
#
# 構成: [Sub(左,PBP)] [Main(右)]

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === 設定 (モニタ接続後に確定する) ===

# UUID (BetterDisplay list で取得)
SUB_UUID="TODO"       # サブモニタ(左) の UUID

# --- M3 Air ---
# (PBP切替では入力値は不要、0x7D のみ操作)
# M2 Max 用: SUB_UUID のみ変更

# === 現在の PBP 状態を取得 ===
current_pbp=$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x7D 2>/dev/null || echo "0")

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ
  $BD set -uuid="$SUB_UUID" -ddc -vcp=0x7D -value=0
  osascript -e 'display notification "PBP オフ" with title "Desktop Switcher"'
else
  # PBP オフ → オン
  $BD set -uuid="$SUB_UUID" -ddc -vcp=0x7D -value=2

  # PBPオン後: connected 管理は watchdog に任せる
  # PBP切替直後は DDC が不安定なため、ここでは触らない

  osascript -e 'display notification "PBP オン" with title "Desktop Switcher"'
fi
