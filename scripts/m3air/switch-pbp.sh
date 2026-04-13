#!/bin/bash
# Key3: PBP切替（トグル） - M3 Air 用
# サブモニタ（左）の PBPオン/オフを切り替える
# 入力設定(0x60, 0x7E)はPBP切替で維持されるため触らない

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

# === 自分のメインモニタ入力値 ===
MY_MAIN_INPUT=$MAIN_AIR   # M3 Air は TB

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

# 書き込み後に読み戻して一致するまで最大 3 回リトライする。
# BenQ が書き込みを silent drop するケースや PBP 遷移直後の不安定期に対応。
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

# === 主ディスプレイ設定 ===
set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

# === メインPC判定 (メインモニタの 0x60 から) ===
current_main=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
is_self_main=0
if [ "$current_main" = "$MY_MAIN_INPUT" ]; then
  is_self_main=1
fi

# メインPC / 他PC の Sub 入力値を決定
if [ "$current_main" = "$MAIN_AIR" ]; then
  SUB_MAIN_PC=$SUB_AIR    # メインPCはAir → Sub側もAir(TB)
  SUB_OTHER_PC=$SUB_MAX
else
  SUB_MAIN_PC=$SUB_MAX
  SUB_OTHER_PC=$SUB_AIR
fi

# === 現在の PBP 状態を取得 ===
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

if [ "$current_pbp" = "2" ]; then
  # PBP オン → オフ
  # 順序: 先に 0x60=メインPC にして [main|main] 状態にしてから PBP off
  # → 他PCの瞬間露出を避ける
  sub_set_verified 0x60 $SUB_MAIN_PC
  sub_set_verified 0x7D 0
  NEW_PBP=0
  osascript -e 'display notification "PBP オフ" with title "Desktop Switcher"'
else
  # PBP オフ → オン
  # switch-main.sh は PBP off 時に 0x7E を書けないため、ここで 0x7E=メインPC
  # を明示的に書く (silent drop 対策は sub_set_verified が担う)。
  sub_set_verified 0x7D 2
  sub_set_verified 0x7E $SUB_MAIN_PC
  sub_set_verified 0x60 $SUB_OTHER_PC
  NEW_PBP=2
  osascript -e 'display notification "PBP オン" with title "Desktop Switcher"'
fi

# === PBP切替後にメインモニタを主ディスプレイに復帰 (自分がメインの場合のみ) ===
# PBP切替時に macOS が主ディスプレイを reassign してしまう対策
if [ "$is_self_main" = "1" ]; then
  sleep 1
  set_main_display
fi
