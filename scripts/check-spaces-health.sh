#!/bin/bash
# Spaces 健全性診断: macOS の Spaces 構成に「幽霊ディスプレイ」が残っていないか調べる。
# 両方の Mac で同じものを実行できる。
#
#   bash scripts/check-spaces-health.sh
#
# Mission Control が開かない / フルスクリーンスペースに切り替えられない時に、
# まずこれを実行して「幽霊エントリが原因か否か」を切り分ける。
#
# 背景:
#   BD が portID 変化で UUID を再採番すると、macOS からは「旧 UUID の display が
#   消えて新 UUID の display が現れた」ように見える。connected=off のまま世代交代
#   すると、旧 UUID の Spaces エントリが Current Space を持たない残骸として残る。
#   Mission Control は全ディスプレイの current space を列挙してから合成するため、
#   current space が nil のエントリが混ざると起動できなくなる (2026-08-27 に発生)。

BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

echo "=============================================="
echo " Spaces 健全性診断"
echo "=============================================="
echo

echo "── 1. BetterDisplay が追跡中のディスプレイ ──"
if pgrep -x BetterDisplay >/dev/null; then
  $BD get -identifiers 2>/dev/null \
    | grep -E '"UUID"|"alphanumericSerial"|"name"' \
    | sed -e 's/^ *//' -e 's/,$//'
else
  echo "  ⚠️  BetterDisplay 本体が起動していません"
fi
echo

echo "── 2. 物理的に接続されているディスプレイ ──"
system_profiler SPDisplaysDataType 2>/dev/null \
  | grep -E "^ {8}[A-Za-z].*:$|Resolution:|Main Display:" \
  | sed -e 's/^ *//'
echo

echo "── 3. macOS Spaces の構成 ──"
python3 - <<'PYEOF'
import subprocess, plistlib, sys

try:
    out = subprocess.run(['defaults', 'export', 'com.apple.spaces', '-'],
                         capture_output=True, check=True).stdout
    d = plistlib.loads(out)
except Exception as e:
    print(f"  ⚠️  読み取り失敗: {e}")
    sys.exit(0)

md = d.get('SpacesDisplayConfiguration', {}).get('Management Data', {})
mode = md.get('Management Mode')
print(f"  Management Mode: {mode}  "
      f"({'ディスプレイごとに個別の Space = ON' if mode == 1 else 'OFF'})")
print()

ghosts = []
for mon in md.get('Monitors', []):
    ident = mon.get('Display Identifier')
    cur = mon.get('Current Space')
    spaces = mon.get('Spaces', [])

    if cur is None:
        ghosts.append(ident)
        print(f"  👻 {ident}")
        print(f"      Current Space なし / Spaces {len(spaces)} 件  ← 幽霊エントリ")
    else:
        print(f"  ✅ {ident}")
        print(f"      Current Space id={cur.get('ManagedSpaceID')} / Spaces {len(spaces)} 件")
        for s in spaces:
            kind = 'フルスクリーン' if s.get('type') == 4 else 'デスクトップ  '
            pid = s.get('pid')
            owner = ''
            if pid:
                try:
                    owner = subprocess.run(['ps', '-o', 'comm=', '-p', str(pid)],
                                           capture_output=True, text=True).stdout.strip()
                    owner = f"  ({owner.split('/')[-1]}, pid {pid})"
                except Exception:
                    owner = f"  (pid {pid})"
            print(f"        - {kind} id={s.get('ManagedSpaceID')}{owner}")
    print()

print("──────────────────────────────────────────────")
if ghosts:
    print(f"  ⚠️  幽霊エントリ {len(ghosts)} 件")
    for g in ghosts:
        print(f"       {g}")
    print()
    print("  幽霊がある = 即座に壊れる、ではありません。Dock を再起動すると")
    print("  メモリ上の構成が組み直されて一時的に動きます。ただし残骸が残る限り")
    print("  次の再配置で再発します。")
    print()
    print("  恒久的な対処: ログアウト → 再ログイン")
    print("      WindowServer がメモリ上に構成を保持しているため、")
    print("      killall Dock や plist 編集では消えません。")
    print()
    print("  今まさに Mission Control が開かない場合の応急処置: killall Dock")
else:
    print("  ✅ 幽霊エントリなし。Spaces 構成は健全です。")
print("──────────────────────────────────────────────")
PYEOF
echo

echo "── 4. watchdog の状態 ──"
if launchctl list 2>/dev/null | grep -q desktop-watchdog; then
  echo "  ✅ 常駐中: $(launchctl list | grep desktop-watchdog)"
else
  echo "  ⚠️  常駐していません"
fi

if [ -f /tmp/desktop-watchdog.state ]; then
  echo "  最後に解決した UUID:"
  sed 's/^/    /' /tmp/desktop-watchdog.state
else
  echo "  状態ファイルなし (/tmp/desktop-watchdog.state)"
fi

if [ -s /tmp/desktop-watchdog.out.log ]; then
  echo "  直近のログ (最大 10 行):"
  tail -10 /tmp/desktop-watchdog.out.log | sed 's/^/    /'
else
  echo "  ログは空 (平常時は無言なので正常)"
fi
echo

echo "── 5. Mission Control のショートカット設定 ──"
python3 - <<'PYEOF'
import subprocess, plistlib
NAMES = {32: 'Mission Control', 33: 'アプリケーションウインドウ',
         79: '左のスペースへ移動', 81: '右のスペースへ移動'}
try:
    out = subprocess.run(['defaults', 'export', 'com.apple.symbolichotkeys', '-'],
                         capture_output=True, check=True).stdout
    hk = plistlib.loads(out)['AppleSymbolicHotKeys']
    for k, label in NAMES.items():
        v = hk.get(str(k), {})
        mark = '✅' if v.get('enabled') else '❌'
        print(f"  {mark} {label}")
except Exception as e:
    print(f"  ⚠️  読み取り失敗: {e}")
PYEOF
