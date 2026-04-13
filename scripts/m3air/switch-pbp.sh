#!/bin/bash
# Key3: PBP切替（トグル） - M3 Air 用
# サブモニタ（左）の PBPオン/オフを切り替える
# 入力設定(0x60, 0x7E)はPBP切替で維持されるため触らない

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M3 Air から見た値) ===
MAIN_UUID="2DF75969-A2F5-4608-A9B4-429B3A3CA4BB"
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# === 自分のメインモニタ入力値 ===
MY_MAIN_INPUT=21   # M3 Air は TB

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

# === 主ディスプレイ設定 ===
apply_primary_display() {
  local pbp=$1
  if [ "$pbp" = "2" ]; then
    displayplacer \
      "id:$MAIN_UUID res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" \
      "id:$SUB_UUID_ON res:1280x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(-1280,0) degree:0" \
      >/dev/null 2>&1 || true
  else
    displayplacer \
      "id:$MAIN_UUID res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" \
      "id:$SUB_UUID_OFF res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(-2560,0) degree:0" \
      >/dev/null 2>&1 || true
  fi
}

# === 自分が現在メインか判定 ===
current_main=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
is_self_main=0
if [ "$current_main" = "$MY_MAIN_INPUT" ]; then
  is_self_main=1
fi

# === 現在の PBP 状態を取得 ===
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_pbp" = "2" ]; then
  sub_set 0x7D 0
  NEW_PBP=0
  osascript -e 'display notification "PBP オフ" with title "Desktop Switcher"'
else
  sub_set 0x7D 2
  NEW_PBP=2
  osascript -e 'display notification "PBP オン" with title "Desktop Switcher"'
fi

# === PBP切替後に主ディスプレイ設定 (自分がメインの場合のみ) ===
# PBP切替直後は DDC / ディスプレイ認識が不安定なので待つ
if [ "$is_self_main" = "1" ]; then
  sleep 3
  apply_primary_display "$NEW_PBP"
fi
