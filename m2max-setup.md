# M2 Max セットアップ手順

M3 Air 側のセットアップが完了済みの状態で、M2 Max 側を同じ構成に仕上げるための手順。

## 前提

- 物理配線が `接続構成` (switching-design.md) の通りになっていること (Max → メインモニタ HDMI / Max → サブモニタ DP)
- Corne キーボード を M2 Max に接続できる状態 (KVM 物理スイッチ / USB 直挿し)

## 1. 必要ツールのインストール

```bash
# Homebrew (未導入なら先に)
# https://brew.sh の手順でインストール

brew install --cask betterdisplay
brew install --cask hammerspoon
brew install displayplacer
```

BetterDisplay 起動後に必要な権限 (アクセシビリティ / 画面収録) をシステム設定で許可。

## 2. リポジトリを clone

```bash
mkdir -p ~/Documents/projects
cd ~/Documents/projects
git clone <このリポジトリのURL> desktop_setup
cd desktop_setup
```

## 3. UUID の確認

scripts/m2max/*.sh の冒頭に定義済みの UUID が現在の M2 Max 環境と一致するか確認する。

```bash
BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
$BD get -identifiers
```

出力のうち PD2730S 2台 (メイン / サブ) の UUID と以下を突き合わせる:

- `MAIN_UUID` — メインモニタ (右、PBPなし)
- `SUB_UUID_OFF` — サブモニタ PBP オフ状態
- `SUB_UUID_ON` — サブモニタ PBP オン状態

UUID が変わっていたら scripts/m2max/switch-main.sh / switch-pbp.sh / display-watchdog.sh の先頭を書き換える。

> サブモニタは **PBP のオン/オフを一度切替えて両 UUID を取得する**必要がある点に注意。

## 4. displayplacer の ID 確認

```bash
displayplacer list
```

メインモニタ (PD2730S、右側) の persistent screen id を控えておく。現状のスクリプトは `BetterDisplay -main=on` を使っているので displayplacer の ID は必須ではないが、主ディスプレイ固定の代替実装に備えてメモしておくと良い。

## 5. スクリプトの実機動作確認

以下を順番に単独実行し、期待状態になるか確認:

```bash
# 現在の状態を dump
BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
$BD get -uuid=<MAIN_UUID> -ddc -vcp=0x60
$BD get -uuid=<SUB_UUID_OFF or ON> -ddc -vcp=0x7D
$BD get -uuid=<SUB_UUID_OFF or ON> -ddc -vcp=0x60
$BD get -uuid=<SUB_UUID_OFF or ON> -ddc -vcp=0x7E

# テスト
bash scripts/m2max/switch-main.sh    # メイン入替 (Key2)
bash scripts/m2max/switch-pbp.sh     # PBP切替 (Key3)
```

switching-design.md の「状態定義」表と照合して、4状態 (S1/S3/S7/S9) 全てに到達できることを確認する。

> M3 Air 側で既に発見済みの主要バグ (0x7E silent drop、チェーン実行時の左右逆転など) は対策済みで `sub_set_verified` / `main_get_input` / `main_set_input` が組み込まれている。再テストで新たに問題が出たらログ (`sub_set_verified mismatch`) を見て調査する。

## 6. Hammerspoon 設定

`~/.hammerspoon/init.lua` を作成:

```lua
require("hs.ipc")

local SCRIPT_DIR = os.getenv("HOME") .. "/Documents/projects/desktop_setup/scripts/m2max"

local function runScript(name)
  return function()
    hs.task.new("/bin/bash", nil, { SCRIPT_DIR .. "/" .. name }):start()
  end
end

hs.hotkey.bind({}, "f19", runScript("switch-main.sh"))
hs.hotkey.bind({}, "f20", runScript("switch-pbp.sh"))

hs.alert.show("Desktop Switcher loaded")
```

**注意**: キーは **f19 / f20** (macOS / Hammerspoon は F20 までしかサポートしない)。Vial 側で Corne Adjust レイヤーにも同じキーを配置すること。

### Hammerspoon 起動と権限

```bash
open -a Hammerspoon
```

初回起動時にアクセシビリティ権限の許可を求められるので、システム設定 → プライバシーとセキュリティ → アクセシビリティ で許可。

動作確認:

```bash
hs -c 'return hs.accessibilityState()'          # → true であること
hs -c 'return #hs.hotkey.getHotkeys()'          # → 2 であること
```

自動起動を有効化:

```bash
hs -c 'hs.autoLaunch(true)'
```

## 7. display-watchdog を launchd で常駐起動

### TCC 対策 (重要)

`launchctl` から起動される `/bin/bash` は macOS の TCC により `~/Documents` 配下にアクセスできない (`Operation not permitted`)。スクリプトを TCC 保護外にコピーして plist はそちらを参照する。

```bash
mkdir -p ~/.local/bin
cp scripts/m2max/display-watchdog.sh ~/.local/bin/desktop-watchdog-m2max.sh
chmod +x ~/.local/bin/desktop-watchdog-m2max.sh
```

### plist 作成

`~/Library/LaunchAgents/com.masayaabe.desktop-watchdog.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.masayaabe.desktop-watchdog</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/<ユーザ名>/.local/bin/desktop-watchdog-m2max.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/desktop-watchdog.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/desktop-watchdog.err.log</string>
</dict>
</plist>
```

### 起動と確認

```bash
launchctl load ~/Library/LaunchAgents/com.masayaabe.desktop-watchdog.plist
sleep 2
launchctl list | grep desktop-watchdog      # pid が表示されること
pgrep -fl desktop-watchdog-m2max             # bash プロセスが走っていること
cat /tmp/desktop-watchdog.err.log            # 空であること
```

### 動作テスト

```bash
BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
MAIN_UUID="<M2 Max 側の MAIN_UUID>"

# わざと connected=off にして watchdog が on に戻すか確認
$BD set -uuid=$MAIN_UUID -connected=off
sleep 6
$BD get -uuid=$MAIN_UUID -connected         # → on に戻っていれば OK
```

PBP オンで、かつサブモニタの状態的にメイン表示が必要なときに limited されるロジックなので、事前に S1 / S3 のどちらかに居ることを確認してからテストすると分かりやすい。

### watchdog のロジックを修正したときの再反映

```bash
cp scripts/m2max/display-watchdog.sh ~/.local/bin/desktop-watchdog-m2max.sh
launchctl kickstart -k gui/$(id -u)/com.masayaabe.desktop-watchdog
```

## 8. Vial / Corne キーマップ

Vial で Corne の Adjust レイヤーに以下を配置:

| キー | 機能 |
|---|---|
| `F19` | switch-main.sh (Key2: メイン入替) |
| `F20` | switch-pbp.sh (Key3: PBP切替) |

両 Mac 共通 (KVM 切替後に同じキーがそのまま使える)。

## 9. リポジトリ更新の反映手順

M3 Air 側での修正が GitHub に push された後、M2 Max 側で変更を取り込むときの手順。

### 基本 (スクリプト修正のみ)

```bash
cd ~/Documents/projects/desktop_setup
git pull
```

`scripts/m2max/switch-main.sh` / `switch-pbp.sh` の修正はこれだけで反映される (Hammerspoon は `~/.hammerspoon/init.lua` から直接リポジトリ内のスクリプトを実行するため)。

### watchdog の修正を含む場合 (重要)

`scripts/m2max/display-watchdog.sh` が変更された場合は、launchd が参照しているコピー (`~/.local/bin/desktop-watchdog-m2max.sh`) を再生成 + kickstart する必要がある。

```bash
cd ~/Documents/projects/desktop_setup
git pull
cp scripts/m2max/display-watchdog.sh ~/.local/bin/desktop-watchdog-m2max.sh
launchctl kickstart -k gui/$(id -u)/com.masayaabe.desktop-watchdog
# 確認
sleep 2
launchctl list | grep desktop-watchdog      # pid が更新されていること
pgrep -fl desktop-watchdog-m2max             # 新しい bash プロセスが走っていること
```

> なぜ再コピーが必要か: launchd から起動される `/bin/bash` は macOS の TCC で `~/Documents` 配下にアクセスできないため、スクリプトの実体は `~/.local/bin` に置いている (セクション 7 参照)。`git pull` だけではこちらは更新されない。

### Hammerspoon init.lua の修正を含む場合

```bash
cd ~/Documents/projects/desktop_setup
git pull
# init.lua は ~/.hammerspoon/ にあるのでリポジトリ外。手動で差分を反映してから:
hs -c 'hs.reload()'
```

### まとめ (チートシート)

| 変更対象 | 必要な追加手順 |
|---|---|
| `scripts/m2max/switch-*.sh` | なし (git pull のみ) |
| `scripts/m2max/display-watchdog.sh` | `~/.local/bin/` へ再コピー + launchctl kickstart |
| `~/.hammerspoon/init.lua` | 手動反映 + `hs -c 'hs.reload()'` |
| `plist` (LaunchAgent) | `launchctl unload && load` |

## 10. 最終チェック

- [ ] 4状態 (S1/S3/S7/S9) を Corne ショートカットだけで行き来できる
- [ ] PBP オン時に「自分がサブ側」になると幽霊スペースが生じない (watchdog が connected=off に補完)
- [ ] launchd watchdog の logs (`/tmp/desktop-watchdog.{out,err}.log`) に異常がない
- [ ] 再起動後に Hammerspoon と watchdog が自動起動する
