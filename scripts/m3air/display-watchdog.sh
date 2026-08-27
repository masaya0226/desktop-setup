#!/bin/bash
# Display Watchdog: サブモニタの状態を見てメインモニタの connected を管理 - M3 Air 用
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
MY_SUB_INPUT=21   # M3 Air は TB

# === 幽霊スペースエントリ対策 (2026-08-27 の障害を受けて追加) ===
# BD が UUID を再採番すると、macOS からは「旧 UUID の display が消えて、
# 新 UUID の display が現れた」ように見える。connected=off のまま世代交代が
# 起きると、旧 UUID の Spaces エントリが Current Space を持たない残骸として
# 永久に残り、Mission Control が起動不能・フルスクリーンスペースへ切替不能になる。
#
# UUID ハードコード時代はこれが起きなかった。世代交代すると BD への書き込みが
# 全て Failed. になり、結果として connected を触らなくなっていたため。
# 動的解決 (2026-08) で追従できるようになった副作用として顕在化した。
#
# ここでは以下の 2 段構えで対処する:
#   1. 世代交代を検知したら、しばらく connected を触らない (SETTLE_CYCLES)
#      → portID がバタついている最中の付け外しで残骸を量産しない
#   2. 残骸が生まれてしまった場合は定期チェックで検出し通知する
#      → Mission Control が壊れる前に気づける
STATE_FILE=/tmp/desktop-watchdog.state
SETTLE_CYCLES=3            # 世代交代後に connected 書き込みを止める周期数 (x4秒)
GHOST_CHECK_EVERY=60       # 幽霊エントリを調べる周期間隔 (x4秒 = 4分)
GHOST_RENOTIFY_SEC=3600    # 同じ幽霊で通知を繰り返さない間隔

PREV_MAIN=""
PREV_SUB=""
settle_left=0
cycle=0
last_ghost_notify=0

# === ログと通知 ===
# StandardOutPath (/tmp/desktop-watchdog.out.log) に落ちる。
# 常駐プロセスなので平常時は無言、状態が変わった時だけ書く。
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

notify() {
  osascript -e "display notification \"$1\" with title \"Desktop Switcher\"" 2>/dev/null || true
}

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

# === 前回解決した UUID の永続化 ===
# 世代交代の検知に使う。/tmp に置くのは意図的で、再起動でクリアされてよい。
# 再起動時は macOS 側の Spaces も作り直されるため、比較対象が無くて正しい。
load_prev_uuids() {
  # shellcheck disable=SC1090
  [ -f "$STATE_FILE" ] && . "$STATE_FILE" 2>/dev/null || true
}

save_prev_uuids() {
  printf 'PREV_MAIN=%s\nPREV_SUB=%s\n' "$MAIN_UUID" "$SUB_UUID" > "$STATE_FILE" 2>/dev/null || true
}

# === UUID を引き直し、世代交代を検知する ===
# 生の resolve_display_uuids ではなくこちらを使うこと。
# 解決に失敗した場合は「世代交代」ではなく単なる読み取り失敗なので、
# PREV_* を上書きしない (次に引けた時に正しく比較できるようにする)。
resolve_and_track() {
  resolve_display_uuids || return 1

  if [ -n "$PREV_MAIN" ] && { [ "$MAIN_UUID" != "$PREV_MAIN" ] || [ "$SUB_UUID" != "$PREV_SUB" ]; }; then
    log "UUID 世代交代を検知: main ${PREV_MAIN:-?} -> ${MAIN_UUID} / sub ${PREV_SUB:-?} -> ${SUB_UUID}"
    notify "BetterDisplay が UUID を再採番しました。幽霊スペース防止のため connected 書き込みを $(( SETTLE_CYCLES * 4 )) 秒止めます。"
    settle_left=$SETTLE_CYCLES
  fi

  PREV_MAIN=$MAIN_UUID
  PREV_SUB=$SUB_UUID
  save_prev_uuids
  return 0
}

# === 幽霊スペースエントリの検出 ===
# com.apple.spaces の Monitors は各要素が "Display Identifier" を持ち、
# 生きているものだけが "Current Space" を持つ。差分がそのまま幽霊の数になる。
# defaults + grep だけで済むので python 等を起動せずに判定できるが、
# 4 秒ループから毎回叩くには重いので GHOST_CHECK_EVERY で間引いて呼ぶ。
count_ghost_spaces() {
  local out ids curs
  out=$(defaults read com.apple.spaces SpacesDisplayConfiguration 2>/dev/null) || { echo 0; return; }
  ids=$(printf '%s\n' "$out" | grep -c '"Display Identifier"')
  curs=$(printf '%s\n' "$out" | grep -c '"Current Space"')
  if [ "$ids" -gt "$curs" ]; then
    echo $(( ids - curs ))
  else
    echo 0
  fi
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

load_prev_uuids
resolve_and_track || true

while true; do
  cycle=$(( cycle + 1 ))

  if [ -e "$LOCK" ]; then
    age=$(( $(date +%s) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
    if [ "$age" -gt 30 ]; then
      rm -f "$LOCK"
    else
      sleep 2
      continue
    fi
  fi

  # 幽霊エントリの定期チェック。connected 制御とは独立した健全性監視なので、
  # DDC が読めていようがいまいが回す。
  if [ $(( cycle % GHOST_CHECK_EVERY )) -eq 0 ]; then
    ghosts=$(count_ghost_spaces)
    if [ "$ghosts" -gt 0 ]; then
      now=$(date +%s)
      if [ $(( now - last_ghost_notify )) -ge "$GHOST_RENOTIFY_SEC" ]; then
        log "幽霊スペースエントリを ${ghosts} 件検出 (Current Space を持たない Monitor)"
        notify "幽霊ディスプレイ ${ghosts} 件を検出。Mission Control が壊れる予兆です。ログアウト→再ログインで解消します。"
        last_ghost_notify=$now
      fi
    fi
  fi

  # UUID 未解決なら引き直し。BD host 停止中などはここで空振りする。
  if [ -z "$SUB_UUID" ] || [ -z "$MAIN_UUID" ]; then
    resolve_and_track || { sleep 4; continue; }
  fi

  pbp=$(sub_get 0x7D)
  sub_main=$(sub_get 0x60)

  if [ -z "$pbp" ] || [ -z "$sub_main" ]; then
    # 空読み = UUID が変わった / BD host 不在 のどちらか。引き直して次周期へ。
    resolve_and_track || true
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
    if [ "$settle_left" -gt 0 ]; then
      # UUID がバタついている最中の付け外しが幽霊エントリを量産する。
      # 落ち着くまで待ってから書く (数周期遅れても実害はない)。
      log "UUID 安定化待ち (残り ${settle_left} 周期): connected=${should_be} の書き込みを見送り"
    else
      $BD set -uuid="$MAIN_UUID" -connected=$should_be 2>/dev/null || true
    fi
  fi

  [ "$settle_left" -gt 0 ] && settle_left=$(( settle_left - 1 ))

  sleep 4
done
