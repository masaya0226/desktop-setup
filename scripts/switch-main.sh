#!/bin/bash
# Key2: メイン入替（トグル）
# 現在のメインPCを判定し、もう一方に切り替える
# PBPオン時はサブモニタの左右入替も行う、PBPオフ時は全入力切替
#
# M3 Air 用。M2 Max 用は MY_MAIN_INPUT, MY_SUB_INPUT を変更する。
#
# 構成: [Sub(左,PBP)] [Main(右)]
# PBP時: Sub左(0x60)=他PC, Sub右(0x7E)=メインPC

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === 設定 (モニタ接続後に確定する) ===

# UUID (BetterDisplay list で取得)
MAIN_UUID="TODO"      # メインモニタ(右) の UUID
SUB_UUID="TODO"       # サブモニタ(左) の UUID
# PBPオン時の SUB UUID が異なる場合はここに設定:
# SUB_UUID_PBP="TODO"

# 入力値定数 (各モニタの DDC 0x60 値)
MAIN_AIR=0            # メインモニタ: M3 Air の入力値
MAIN_MAX=0            # メインモニタ: M2 Max の入力値
SUB_AIR=0             # サブモニタ: M3 Air の入力値
SUB_MAX=0             # サブモニタ: M2 Max の入力値

# --- M3 Air ---
MY_MAIN_INPUT=$MAIN_AIR    # 自分のメインモニタ入力値
MY_SUB_INPUT=$SUB_AIR      # 自分のサブモニタ入力値
# M2 Max 用:
# MY_MAIN_INPUT=$MAIN_MAX
# MY_SUB_INPUT=$SUB_MAX

# displayplacer によるメインディスプレイ設定 (displayplacer list で取得)
# DISPLAYPLACER_MAIN_ID="TODO"

# === メインモニタが connected=off の場合、一時的に on にして状態取得 ===
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "on")
if [ "$main_connected" = "off" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
  sleep 1
fi

# === 現在の状態を取得 ===
current_main=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
current_pbp=$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x7D 2>/dev/null || echo "0")

if [ "$current_main" = "$MAIN_AIR" ]; then
  # 現在 Air がメイン → Max に切替
  TARGET_MAIN=$MAIN_MAX
  TARGET_SUB_LEFT=$SUB_AIR    # Sub左(0x60)=他PC(Air)
  TARGET_SUB_RIGHT=$SUB_MAX   # Sub右(0x7E)=メインPC(Max)
  NOTIFY="M2 Max に切替"
  TARGET_IS_MY="$MY_MAIN_INPUT=$MAIN_MAX"
else
  # 現在 Max がメイン → Air に切替
  TARGET_MAIN=$MAIN_AIR
  TARGET_SUB_LEFT=$SUB_MAX    # Sub左(0x60)=他PC(Max)
  TARGET_SUB_RIGHT=$SUB_AIR   # Sub右(0x7E)=メインPC(Air)
  NOTIFY="M3 Air に切替"
  TARGET_IS_MY="$MY_MAIN_INPUT=$MAIN_AIR"
fi

# === メインモニタの入力切替 ===
$BD set -uuid="$MAIN_UUID" -ddc -vcp=0x60 -value=$TARGET_MAIN

# === サブモニタの入力切替 ===
if [ "$current_pbp" = "2" ]; then
  # PBPオン: 左右入替（0x7E を先に変更、次に 0x60）
  sleep 1
  $BD set -uuid="$SUB_UUID" -ddc -vcp=0x7E -value=$TARGET_SUB_RIGHT
  sleep 1
  $BD set -uuid="$SUB_UUID" -ddc -vcp=0x60 -value=$TARGET_SUB_LEFT
else
  # PBPオフ: 単純に入力切替
  sleep 1
  $BD set -uuid="$SUB_UUID" -ddc -vcp=0x60 -value=$TARGET_MAIN
fi

# === メインモニタ connected 管理 (幽霊スペース対策) ===
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

# === 主ディスプレイをメインモニタに設定 ===
# TODO: displayplacer コマンドを接続確定後に設定
# displayplacer "id:$DISPLAYPLACER_MAIN_ID origin:(0,0)"

osascript -e "display notification \"$NOTIFY\" with title \"Desktop Switcher\""
