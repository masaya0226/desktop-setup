#!/bin/bash
# Key2: メイン入替（トグル） - M2 Max 用
# 構成: [Sub(左,PBP)] [Main(右)]
# PBP時: Sub左(0x60)=他PC, Sub右(0x7E)=メインPC

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === UUID (M2 Max から見た値) ===
MAIN_UUID="7A782274-C5F3-414C-B90A-41770749B121"
SUB_UUID_OFF="4A8F5105-1777-4D51-8E49-ECDD133C3D7B"
SUB_UUID_ON="C2E62FA2-0938-463E-92B2-FD77960B47C5"

# === 入力値定数 ===
MAIN_AIR=21   # TB
MAIN_MAX=17   # HDMI
SUB_AIR=21    # TB
SUB_MAX=15    # DP

# === 自分の入力値 ===
MY_MAIN_INPUT=$MAIN_MAX
MY_SUB_INPUT=$SUB_MAX

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

# PBP off 時の 0x7E 書き込みは BenQ が silent drop するため、
# 書き込み後に読み戻して一致するまで最大 3 回リトライする。
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

# === 主ディスプレイ設定 (メインモニタを主ディスプレイに固定) ===
set_main_display() {
  $BD set -uuid="$MAIN_UUID" -main=on >/dev/null 2>&1 || true
}

# === メインモニタ DDC ヘルパー (リトライ付き) ===
# チェーン実行や connected=on 復帰直後は DDC が不安定なため、空値や
# "Failed." 出力に対して最大数回リトライする。
main_get_input() {
  local val=""
  for _ in 1 2 3 4 5; do
    val=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
    sleep 1
  done
  return 1
}

main_set_input() {
  local value=$1
  local err
  for _ in 1 2 3; do
    err=$($BD set -uuid="$MAIN_UUID" -ddc -vcp=0x60 -value=$value 2>&1 >/dev/null)
    if [ -z "$err" ] || ! printf '%s' "$err" | grep -qi "fail"; then
      return 0
    fi
    sleep 1
  done
  printf 'main_set_input: DDC write failed: %s\n' "$err" >&2
  return 1
}

# === メインモニタが connected=off の場合、一時的に on にして状態取得 ===
main_connected=$($BD get -uuid="$MAIN_UUID" -connected 2>/dev/null || echo "on")
if [ "$main_connected" = "off" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
  sleep 2
fi

# === 現在の状態を取得 ===
current_main=$(main_get_input || echo "")
current_pbp=$(sub_get 0x7D)
[ -z "$current_pbp" ] && current_pbp=0

# current_main が取れない場合はトグル方向不明のため中断 (誤方向切替防止)
if [ -z "$current_main" ]; then
  osascript -e 'display notification "メインモニタ DDC 読み取り失敗。中断しました。" with title "Desktop Switcher"'
  exit 1
fi

if [ "$current_main" = "$MAIN_AIR" ]; then
  # Air → Max
  TARGET_MAIN=$MAIN_MAX
  TARGET_SUB_MAIN=$SUB_MAX
  TARGET_SUB_OTHER=$SUB_AIR
  NOTIFY="M2 Max に切替"
else
  # Max → Air
  TARGET_MAIN=$MAIN_AIR
  TARGET_SUB_MAIN=$SUB_AIR
  TARGET_SUB_OTHER=$SUB_MAX
  NOTIFY="M3 Air に切替"
fi

# === メインモニタの入力切替 ===
main_set_input $TARGET_MAIN

# === サブモニタの入力切替 ===
if [ "$current_pbp" = "2" ]; then
  # PBP on: Sub左(0x60)=他PC, 右(0x7E)=メインPC
  sleep 1
  sub_set_verified 0x7E $TARGET_SUB_MAIN
  sub_set_verified 0x60 $TARGET_SUB_OTHER
else
  # PBP off: 0x60(表示) のみメインPCに書く
  # 0x7E は PBP off 時に BenQ が書き込みを silent drop するため触らない。
  # 不変条件「0x7E=メインPC」は switch-pbp.sh の PBP on 遷移時に明示的に書き直す。
  sleep 1
  sub_set_verified 0x60 $TARGET_SUB_MAIN
fi

# === メインモニタ connected 管理 (幽霊スペース対策) ===
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  $BD set -uuid="$MAIN_UUID" -connected=on 2>/dev/null || true
else
  $BD set -uuid="$MAIN_UUID" -connected=off 2>/dev/null || true
fi

# === メインモニタを主ディスプレイに復帰 (自分がメインになった場合のみ) ===
if [ "$MY_MAIN_INPUT" = "$TARGET_MAIN" ]; then
  sleep 1
  set_main_display
fi

osascript -e "display notification \"$NOTIFY\" with title \"Desktop Switcher\""
