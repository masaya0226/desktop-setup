#!/bin/bash
# Display Watchdog: サブモニタの状態を見てメインモニタの connected を管理 - M2 Max 用
# サブモニタは常に connected=on なので DDC 読み取り可能。
# 切替スクリプトがカバーしきれないケース（PBP切替後など）の補完。

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# === ディスプレイ識別 (UUID は動的解決) ===
# BD の UUID はハードコード禁止。TB/DP の再列挙で portID が変わると BD が
# 同一個体に別 UUID を採番するため (2026-08 に実際に発生)。
# 常駐プロセスなので、読み取りが空になる度に引き直す。
MAIN_SERIAL="GAS00262019"; MAIN_MODEL="32908"   # メインモニタ (右)
SUB_SERIAL="E1T00045019";  SUB_MODEL="32907"    # サブモニタ (左, PBP)

MAIN_UUID=""
SUB_UUID=""

# === 自分のサブモニタ入力値 ===
MY_SUB_INPUT=15   # M2 Max は DP

# === UUID 動的解決 ===
bd_uuid_by_field() {
  local field=$1 want=$2 uuid="" line val
  while IFS= read -r line; do
    case "$line" in
      '{'|'},{') uuid="" ;;
    esac
    case "$line" in
      *'"UUID"'*)
        val=${line#*: \"}; uuid=${val%\"*} ;;
      *"\"$field\""*)
        val=${line#*: \"}; val=${val%\"*}
        if [ "$val" = "$want" ] && [ -n "$uuid" ]; then
          printf '%s\n' "$uuid"
          return 0
        fi ;;
    esac
  done < <($BD get -identifiers 2>/dev/null)
  return 1
}

resolve_display_uuids() {
  MAIN_UUID=$(bd_uuid_by_field alphanumericSerial "$MAIN_SERIAL") \
    || MAIN_UUID=$(bd_uuid_by_field model "$MAIN_MODEL") \
    || MAIN_UUID=""
  SUB_UUID=$(bd_uuid_by_field alphanumericSerial "$SUB_SERIAL") \
    || SUB_UUID=$(bd_uuid_by_field model "$SUB_MODEL") \
    || SUB_UUID=""
  [ -n "$MAIN_UUID" ] && [ -n "$SUB_UUID" ] && [ "$MAIN_UUID" != "$SUB_UUID" ]
}

# === サブモニタ DDC ヘルパー ===
# 書き込み直後は DDC バスが数秒不安定で空読み・値ズレが起きる (実測)。
# 旧実装は 2 つの UUID を順に試すことで実質リトライになっていたため、
# 単一 UUID 化にあたって明示的なリトライを入れる。
sub_get() {
  local vcp=$1 val
  for _ in 1 2 3; do
    val=$($BD get -uuid="$SUB_UUID" -ddc -vcp=$vcp 2>/dev/null || echo "")
    if [ -n "$val" ]; then
      echo "$val"
      return 0
    fi
    sleep 1
  done
  echo ""
  return 1
}

# === 切替スクリプトとの相互排他ロック ===
# Key2/Key3 実行中は DDC read や connected write を行わない。
# 30 秒以上古いロックは stale とみなして削除する (trap 失敗時の保険)。
LOCK=/tmp/desktop-switcher.lock

resolve_display_uuids || true

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

  # UUID 未解決なら引き直し。BD host 停止中などはここで空振りする。
  if [ -z "$SUB_UUID" ] || [ -z "$MAIN_UUID" ]; then
    resolve_display_uuids || { sleep 4; continue; }
  fi

  pbp=$(sub_get 0x7D)
  sub_main=$(sub_get 0x60)

  if [ -z "$pbp" ] || [ -z "$sub_main" ]; then
    # 空読み = UUID が変わった / BD host 不在 のどちらか。引き直して次周期へ。
    resolve_display_uuids || true
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
