#!/bin/bash
# ディスプレイ識別診断: 切替スクリプトが使う UUID 解決の結果を人間が確認するためのツール。
# 両方の Mac で同じものを実行できる (シリアルはモニタ個体固有なので機種非依存)。
#
#   bash scripts/resolve-displays.sh
#
# 切替が動かなくなったら、まずこれを実行して「メイン/サブが正しく引けているか」
# 「DDC が通っているか」を切り分ける。

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

MAIN_SERIAL="GAS00262019"; MAIN_MODEL="32908"   # メインモニタ (右)
SUB_SERIAL="E1T00045019";  SUB_MODEL="32907"    # サブモニタ (左, PBP)

MAIN_UUID=""
SUB_UUID=""

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

echo "=== BD host ==="
if pgrep -x BetterDisplay >/dev/null; then
  echo "  running (pid $(pgrep -x BetterDisplay | tr '\n' ' '))"
else
  echo "  NOT RUNNING — BD CLI は全て失敗します。BetterDisplay.app を起動してください。"
  exit 1
fi

echo
echo "=== BD が現在追跡しているディスプレイ ==="
$BD get -identifiers 2>/dev/null \
  | grep -E '"(UUID|alphanumericSerial|model|name|registryLocation)"' \
  | sed 's/^  /  /'

echo
echo "=== 解決結果 ==="
if resolve_display_uuids; then
  echo "  OK"
else
  echo "  FAILED — メイン/サブのどちらかが引けていません"
fi
printf '  MAIN (serial %s / model %s) → %s\n' "$MAIN_SERIAL" "$MAIN_MODEL" "${MAIN_UUID:-(未解決)}"
printf '  SUB  (serial %s / model %s) → %s\n' "$SUB_SERIAL" "$SUB_MODEL" "${SUB_UUID:-(未解決)}"

echo
echo "=== DDC 実測 ==="
if [ -n "$MAIN_UUID" ]; then
  echo "  MAIN:"
  printf '    connected  = %s\n' "$($BD get -uuid="$MAIN_UUID" -connected 2>&1)"
  printf '    main       = %s\n' "$($BD get -uuid="$MAIN_UUID" -main 2>&1)"
  printf '    0x60 input = %s\n' "$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>&1)"
fi
if [ -n "$SUB_UUID" ]; then
  echo "  SUB:"
  printf '    connected  = %s\n' "$($BD get -uuid="$SUB_UUID" -connected 2>&1)"
  printf '    0x7D pbp   = %s  (0=off, 2=on)\n' "$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x7D 2>&1)"
  printf '    0x60 input = %s  (PBP時は左半分)\n' "$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x60 2>&1)"
  printf '    0x7E pbpin = %s  (PBP時は右半分 = メインPC)\n' "$($BD get -uuid="$SUB_UUID" -ddc -vcp=0x7E 2>&1)"
fi

echo
echo "参考: 入力値 21=TB(M3 Air) / 17=HDMI(M2 Max, メイン) / 15=DP(M2 Max, サブ)"
