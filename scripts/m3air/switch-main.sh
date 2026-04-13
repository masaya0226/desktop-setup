#!/bin/bash
# Key2: メイン入替（トグル） - M3 Air 用
# 構成: [Sub(左,PBP)] [Main(右)]
# PBP時: Sub左(0x60)=他PC, Sub右(0x7E)=メインPC

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M3 Air から見た値) ===
MAIN_UUID="2DF75969-A2F5-4608-A9B4-429B3A3CA4BB"
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# === 入力値定数 ===
MAIN_AIR=21   # TB
MAIN_MAX=17   # HDMI
SUB_AIR=21    # TB
SUB_MAX=15    # DP

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_AIR
MY_SUB_INPUT=$SUB_AIR

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

# === 主ディスプレイ設定 (Main を主、Sub を左に配置) ===
apply_primary_display() {
  local pbp=$1
  if [ "$pbp" = "2" ]; then
    # PBP on: Sub 半分(1280x1440) を Main の左に
    displayplacer \
      "id:$MAIN_UUID res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" \
      "id:$SUB_UUID_ON res:1280x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(-1280,0) degree:0" \
      >/dev/null 2>&1 || true
  else
    # PBP off: Sub フル(2560x1440) を Main の左に
    displayplacer \
      "id:$MAIN_UUID res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0" \
      "id:$SUB_UUID_OFF res:2560x1440 hz:60 color_depth:8 enabled:true scaling:on origin:(-2560,0) degree:0" \
      >/dev/null 2>&1 || true
  fi
}

# === メインモニタが connected=off の場合、一時的に on にして状態取得 ===
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "on")
if [ "$main_connected" = "off" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
  sleep 1
fi

# === 現在の状態を取得 ===
current_main=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_main" = "$MAIN_AIR" ]; then
  TARGET_MAIN=$MAIN_MAX
  TARGET_SUB_LEFT=$SUB_AIR    # Sub左(0x60)=他PC(Air)
  TARGET_SUB_RIGHT=$SUB_MAX   # Sub右(0x7E)=メインPC(Max)
  NOTIFY="M2 Max に切替"
else
  TARGET_MAIN=$MAIN_AIR
  TARGET_SUB_LEFT=$SUB_MAX
  TARGET_SUB_RIGHT=$SUB_AIR
  NOTIFY="M3 Air に切替"
fi

# === メインモニタの入力切替 ===
$BD set -uuid="$MAIN_UUID" -ddc -vcp=0x60 -value=$TARGET_MAIN

# === サブモニタの入力切替 ===
if [ "$current_pbp" = "2" ]; then
  sleep 1
  sub_set 0x7E $TARGET_SUB_RIGHT
  sleep 1
  sub_set 0x60 $TARGET_SUB_LEFT
else
  sleep 1
  sub_set 0x60 $TARGET_MAIN
fi

# === メインモニタ connected 管理 (幽霊スペース対策) ===
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

# === 主ディスプレイをメインモニタに設定 (自分がメインになった場合のみ) ===
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  sleep 1
  apply_primary_display "$current_pbp"
fi

osascript -e "display notification \"$NOTIFY\" with title \"Desktop Switcher\""
