#!/bin/bash
# Display Watchdog: サブモニタの状態を見てメインモニタの connected を管理
# サブモニタは常に connected=on なので DDC 読み取り可能。
# 切替スクリプトがカバーしきれないケース（PBP切替後など）の補完。
#
# M3 Air 用。M2 Max 用は MY_SUB_INPUT を変更する。
#
# 構成: [Sub(左,PBP)] [Main(右)]

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === 設定 (モニタ接続後に確定する) ===

# UUID (BetterDisplay list で取得)
MAIN_UUID="TODO"      # メインモニタ(右) の UUID
SUB_UUID="TODO"       # サブモニタ(左) の UUID

# 自分のサブモニタ入力値
MY_SUB_INPUT=0        # M3 Air のサブモニタ入力値
# M2 Max 用:
# MY_SUB_INPUT=0

while true; do
  # サブモニタから状態を読む（サブモニタは常に connected=on）
  pbp=$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x7D 2>/dev/null || echo "")
  sub_main=$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")

  # DDC 読み取り失敗ならスキップ
  if [ -z "$pbp" ] || [ -z "$sub_main" ]; then
    sleep 4
    continue
  fi

  # メインモニタのあるべき connected 状態を判定
  current_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "")
  should_be=""

  if [ "$pbp" = "2" ]; then
    # PBPオン時:
    # Sub左(0x60)=他PC → 0x60 が自分ならメインは他PC → メインモニタ=off
    # Sub左(0x60)≠自分 → 0x60 が他PCなら自分がメイン → メインモニタ=on
    if [ "$sub_main" = "$MY_SUB_INPUT" ]; then
      # Sub左(0x60)が自分 = 自分は他PC側 = メインモニタは他PCを表示中
      should_be="off"
    else
      # Sub左(0x60)が他PC = 自分がメインPC = メインモニタは自分を表示中
      should_be="on"
    fi
  else
    # PBPオフ: メインモニタは触らない（S7/S9 で困らないので）
    sleep 4
    continue
  fi

  # 現状とあるべき状態が違う場合だけ操作
  if [ "$current_connected" != "$should_be" ]; then
    $BD set -uuid="$MAIN_UUID" -connected=$should_be 2>/dev/null || true
  fi

  sleep 4
done
