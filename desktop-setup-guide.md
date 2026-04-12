# デスクトップ環境セットアップ手順書（Phase 1：BenQ 1 枚 + 既存 iiyama）

2台の Mac（M2 Max MacBook Pro 14" / M3 MacBook Air）を、Corne ワンキーで切り替えられる常時稼働環境に構築する手順書。まずは BenQ の 5K モニタ（MA270S または PD2730S）を 1 枚だけ購入し、既存の iiyama と組み合わせて運用する段階的な構成。

## 目標構成

- **中央(Main)**: iiyama XUB2792QSN 27" WQHD（既存）
- **横(Sub)**: BenQ MA270S または PD2730S 27" 5K（新規、PBP で左右分割）
- **Corne キーボード**: BenQ の USB ハブ経由 → KVM で自動ホスト切替
- **MX Ergo マウス**: Bluetooth 複数ペアリング（既存通り）
- **常時稼働**: M3 Air はクラムシェル放置で Claude Code ジョブを実行

Phase 2（将来）で iiyama を BenQ もう 1 枚に置き換える想定だが、本ガイドは Phase 1 のみを扱う。

## 接続トポロジー

```
                 iiyama XUB2792QSN (Main)
                   ├── USB-C ──── M2 Max          (映像 + 給電 + USB、既存)
                   └── HDMI ───── M3 Air          (USB-C→HDMI 変換、映像のみ)

                 BenQ 5K (Sub, PBP 左右分割)
                   ├── Thunderbolt 4 ── M3 Air    (映像 + 96W 給電 + USB、KVM 上流 A)
                   ├── HDMI 2.1 ─────── M2 Max    (USB-C→HDMI、映像のみ)
                   └── USB-C/USB-B ──── M2 Max    (KVM 上流 B、データのみ)

                 BenQ USB ハブ背面
                   └── Corne キーボード
```

KVM は 2 つの上流（TB4 側 = M3 Air、USB-B/USB-C 側 = M2 Max）を持ち、映像入力の切替に連動して Corne の接続先ホストを自動で切り替える。M3 Air は BenQ 経由の TB4 1 本で電源・映像・USB がすべて賄われるのでクラムシェル常時稼働に最適。

---

## Phase 0: 購入リスト

| 品目 | 価格目安 | 備考 |
|---|---|---|
| BenQ MA270S または PD2730S | 15〜20 万円 | MA270S: Nano Gloss、PD2730S: Nano Matte |
| Ergotron LX デスクマウント | 約 20,000 円 | VESA 100×100、アーム単体 |
| USB-C ⇄ USB-C TB4 ケーブル（1m）| 約 5,000 円 | M3 Air → BenQ TB4。Apple 純正または CalDigit 推奨 |
| USB-C ⇄ HDMI 2.1 ケーブル（1.5m）| 約 3,000 円 | M2 Max → BenQ HDMI（8K60 対応品） |
| USB-C ⇄ USB-B（USB 3.0、1.5m）| 約 1,500 円 | M2 Max → BenQ KVM 上流。PD2730S の場合は USB-C ⇄ USB-C で代用可 |
| USB-C ⇄ HDMI（M3 Air → iiyama 用、既存なら不要）| 約 3,000 円 | - |
| 結束バンド・ケーブルトレー | 約 3,000 円 | - |

MA270S は USB 上流が TB4 + 第 2 USB ポートの構成、PD2730S は TB4 + USB-C（データのみ）の構成。実機到着後にポート構成を確認してケーブル種別を確定する。

---

## Phase 1: 購入前・到着前の準備作業

### 1.1 m1ddc のインストールと iiyama の DDC/CI 動作確認

```bash
brew install m1ddc

# 現在繋がっているディスプレイ一覧
m1ddc display list

# iiyama の現在の入力値を取得
m1ddc display "iiyama" get input
```

期待値: 数値（15=USB-C、17=HDMI、18=DisplayPort など、モデルにより異なる）が返ること。値をメモしておく。

### 1.2 Hammerspoon のインストール

```bash
brew install --cask hammerspoon
open -a Hammerspoon
```

システム設定 > プライバシーとセキュリティ > アクセシビリティ に Hammerspoon を追加して許可。M2 Max・M3 Air の両方にインストールする。

### 1.3 Vial の準備

Corne のキーマップは Vial で管理しているため、ビルド環境は不要。Vial アプリが最新版であることを確認する：

https://get.vial.today/

既存のキーマップは念のため Vial の「Save Current Layout」から `.vil` ファイルとしてバックアップしておく。

### 1.4 BenQ Display Pilot 2 のインストール（任意）

BenQ 純正の画面制御ツール。OSD を macOS 上からコントロールできる。ファームウェア更新時にも必要。

https://www.benq.com/en-us/support/downloads-faq/software/display-pilot-2.html

---

## Phase 2: ハードウェア設置

### 2.1 Ergotron LX のデスク取付

- クランプ式: デスク奥の天板に挟み込み
- グロメット式: 既存の穴があればそちらを使用
- アームの高さ: iiyama と BenQ の**下端**を揃える位置に調整

### 2.2 BenQ をアームに取付

- VESA 100×100 プレートで固定
- 設置後、iiyama と並べて左右の角度・高さを仮設定

### 2.3 ケーブル配線

| From | To | ケーブル |
|---|---|---|
| M2 Max Thunderbolt ポート 1 | iiyama USB-C | USB-C ⇄ USB-C（既存） |
| M2 Max Thunderbolt ポート 2 | BenQ HDMI 2.1 | USB-C ⇄ HDMI 2.1 |
| M2 Max Thunderbolt ポート 2（上と同一） | BenQ USB 上流 B | USB-C ⇄ USB-B もしくは USB-C ⇄ USB-C |
| M3 Air Thunderbolt ポート 1 | BenQ Thunderbolt 4 | USB-C ⇄ USB-C（TB4 認証品） |
| M3 Air Thunderbolt ポート 2 | iiyama HDMI | USB-C ⇄ HDMI |
| BenQ USB ハブ背面 | Corne | 既存の USB ケーブル |
| MX Ergo | — | Bluetooth（iiyama/M2 Max/M3 Air の 3 ペアリング） |

M2 Max は TB ポートを 2 つ使う。1 つは iiyama 側、もう 1 つは BenQ の HDMI + KVM 上流を 1 ハブで束ねる形（USB-C 分岐ハブがあればすっきりする）。配線を結束バンドでまとめ、デスク下のケーブルトレーに収める。

---

## Phase 3: モニター OSD 設定

### 3.1 iiyama XUB2792QSN

- **DDC/CI: ON**（Setup Menu > DDC/CI > On）
- **入力ソース自動切替: OFF**（手動制御のため）

### 3.2 BenQ MA270S / PD2730S

**Display メニュー**
- **Input**: 起動時のデフォルト入力を任意に設定（後でスクリプトから切替）
- **PBP**: On（左右 2 分割モード）
- **PBP 左画面のソース**: Thunderbolt（M3 Air）
- **PBP 右画面のソース**: HDMI（M2 Max）

**KVM Switch メニュー**
- **KVM**: On
- **Upstream A**: Thunderbolt 4
- **Upstream B**: USB-C（PD2730S の場合）または USB-B（MA270S の場合）
- **KVM と映像入力を連動**: On（"KVM follows video input" 相当の項目）

**System メニュー**
- **DDC/CI**: On
- **Auto Power Off**: Off（KVM を維持するため）
- **Smart Power**: Off
- **M-book モード**（MA270S のみ）: On（MacBook と色味を揃える）

---

## Phase 4: 切替スクリプト

### 4.1 DDC コード値と UUID の特定

m1ddc はディスプレイ名での指定に対応しておらず、**番号（接続順で変わる）または UUID** で指定する。UUID は安定しているため UUID を使う。

**重要な注意点**:
- UUID は **Mac ごとに異なる**（同じモニタでも M2 Max と M3 Air で UUID が違う）
- BenQ PD2730S は **PBP オン/オフで異なる UUID** を持つ（2 台の別ディスプレイとして認識される）
- 各 Mac で `m1ddc display list` を実行し、UUID と入力値を個別に記録する必要がある

**UUID の確認手順**（両 Mac で実行）:

```bash
# ディスプレイ一覧（UUID 付き）
m1ddc display list

# 各ディスプレイの現在の入力値を UUID で取得
m1ddc display <UUID> get input

# 入力切替のテスト
m1ddc display <UUID> set input 17   # HDMI
m1ddc display <UUID> set input 19   # USB-C（iiyama）
m1ddc display <UUID> set input 21   # Thunderbolt（BenQ）
```

**M3 Air 側（確認済み）**:

| ディスプレイ | モード | UUID | 入力値 |
|---|---|---|---|
| BenQ PD2730S | PBP オフ | `2DF75969-A2F5-4608-A9B4-429B3A3CA4BB` | TB=21, HDMI=17 |
| BenQ PD2730S | PBP オン | `4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20` | TB=21, HDMI=17 |
| iiyama PL2792QN | — | `180CEA86-E5B7-4FC4-B2D6-5BFC6C9D81B5` | HDMI=17, TYPEC=19 |

M3 Air → iiyama は TYPEC（値 19）、M3 Air → BenQ は TB（値 21）で接続。

**M2 Max 側（要確認）**:

M2 Max でも同じ手順で UUID と入力値を記録する。PBP モードで `m1ddc display list` を実行し、各 UUID をメモ。M2 Max → iiyama は USB-C、M2 Max → BenQ は HDMI で接続しているので、対応する入力値を確認する。

### 4.2 切替スクリプト（DDC 入力切替のみ）

切替スクリプトは「モニタの入力を切り替える」ことだけに集中させる。BetterDisplay の論理接続/切断は別途 watchdog（4.3）が担当するため、ここには含めない。ディスプレイは UUID で指定する。

**M3 Air 用** `~/scripts/switch-to-m2max.sh`:

```bash
#!/bin/bash
set -e

# M3 Air から見た UUID（Mac ごとに異なる）
IIYAMA_UUID="180CEA86-E5B7-4FC4-B2D6-5BFC6C9D81B5"
BENQ_PBP_UUID="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# M2 Max が使っている入力値
IIYAMA_INPUT_M2MAX=19       # iiyama USB-C（要確認：M2 Max → iiyama の入力値）
BENQ_INPUT_M2MAX=17         # BenQ HDMI

m1ddc display $IIYAMA_UUID set input $IIYAMA_INPUT_M2MAX
m1ddc display $BENQ_PBP_UUID set input $BENQ_INPUT_M2MAX

osascript -e 'display notification "M2 Max に切替" with title "Desktop Switcher"'
```

**M3 Air 用** `~/scripts/switch-to-m3air.sh`:

```bash
#!/bin/bash
set -e

IIYAMA_UUID="180CEA86-E5B7-4FC4-B2D6-5BFC6C9D81B5"
BENQ_PBP_UUID="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# M3 Air が使っている入力値
IIYAMA_INPUT_M3AIR=19       # iiyama TYPEC（確認済み）
BENQ_INPUT_M3AIR=21         # BenQ Thunderbolt（確認済み）

m1ddc display $IIYAMA_UUID set input $IIYAMA_INPUT_M3AIR
m1ddc display $BENQ_PBP_UUID set input $BENQ_INPUT_M3AIR

osascript -e 'display notification "M3 Air に切替" with title "Desktop Switcher"'
```

**M2 Max 用**: 同じ構造で UUID と入力値を M2 Max 側で確認した値に置き換える。

実行権限を付与:
```bash
chmod +x ~/scripts/switch-to-m2max.sh ~/scripts/switch-to-m3air.sh
```

**PBP 動作時の注意**: PBP が On のまま `set input` を発行すると、BenQ によってはアクティブ入力（=KVM の上流）だけ切り替わる場合と、PBP が解除されて単画面になる場合がある。動作を実機で確認し、期待通りでなければ以下で調整：

- **PBP 固定 + KVM だけ切替**: `kvm-switch` 系の DDC コマンドで KVM のみを切り替える（BenQ は `0xE5` 付近のレジスタに KVM スイッチを持つことが多い）
- **PBP 解除 → 単画面切替**: `set pbp off` → `set input X` → 必要なら `set pbp on`

普段は PBP で常時両 Mac を表示し、**アクティブ（KVM 上流）だけをスクリプトで切替**する運用が最もシンプル。

### 4.3 Display Watchdog（BetterDisplay 論理接続の自動制御）

入力切替時に非アクティブ Mac 側でも論理的にモニタを切断するため、各 Mac で独立して動く watchdog スクリプトを常駐させる。SSH 不要、ネットワーク通信なしで動作する。

**仕組み**

各 Mac が数秒おきに `m1ddc` でモニタの現在のアクティブ入力を取得し、自分の入力値と一致していれば接続、一致していなければ切断する。Corne による入力切替にも、物理 OSD ボタンによる切替にも自動で追従する。

**前提**

- BetterDisplay Pro がインストールされている（`betterdisplaycli` コマンドが使える）
- 各 Mac が「自分がモニタに接続している入力値」を知っている（Phase 4.1 で特定済み）

**M3 Air 側スクリプト**

`~/scripts/display-watchdog.sh`:

```bash
#!/bin/bash

# M3 Air から見た UUID（Mac ごとに異なるため各 Mac で書き換えが必要）
IIYAMA_UUID="180CEA86-E5B7-4FC4-B2D6-5BFC6C9D81B5"
BENQ_PBP_UUID="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"

# M3 Air が使っている入力値
MY_IIYAMA_INPUT=19    # iiyama TYPEC（確認済み）
MY_BENQ_INPUT=21      # BenQ Thunderbolt（確認済み）

# BetterDisplay での表示名（betterdisplaycli 用）
IIYAMA_BD_NAME="PL2792QN"
BENQ_BD_NAME="BenQ PD2730S"

check_and_sync() {
  local uuid="$1"
  local my_input="$2"
  local bd_name="$3"

  current_input=$(m1ddc display $uuid get input 2>/dev/null)
  if [ -z "$current_input" ]; then
    return  # DDC 応答なし → 何もしない
  fi

  if [ "$current_input" = "$my_input" ]; then
    betterdisplaycli set --name "$bd_name" --disconnected=false 2>/dev/null || true
  else
    betterdisplaycli set --name "$bd_name" --disconnected=true 2>/dev/null || true
  fi
}

while true; do
  check_and_sync "$IIYAMA_UUID" $MY_IIYAMA_INPUT "$IIYAMA_BD_NAME"
  check_and_sync "$BENQ_PBP_UUID" $MY_BENQ_INPUT "$BENQ_BD_NAME"
  sleep 4
done
```

**M2 Max 側スクリプト**

同じ構造で以下を M2 Max で確認した値に置き換える：

```bash
# M2 Max で m1ddc display list して確認した UUID
IIYAMA_UUID="（M2 Max で要確認）"
BENQ_PBP_UUID="（M2 Max で要確認）"

# M2 Max が使っている入力値
MY_IIYAMA_INPUT=（要確認：M2 Max → iiyama の入力値）
MY_BENQ_INPUT=17      # BenQ HDMI
```

実行権限：

```bash
chmod +x ~/scripts/display-watchdog.sh
```

**launchd で常駐**

`~/Library/LaunchAgents/com.yap.display-watchdog.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yap.display-watchdog</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/yap/scripts/display-watchdog.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/display-watchdog.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/display-watchdog.err</string>
</dict>
</plist>
```

ロード：

```bash
launchctl load ~/Library/LaunchAgents/com.yap.display-watchdog.plist
```

ログで動作確認：

```bash
tail -f /tmp/display-watchdog.err
```

**両 Mac で同じ手順を実施**する。M2 Max 用と M3 Air 用で入力値だけが異なる。

**責務分離の考え方**

- **切替スクリプト（Phase 4.2）**: モニタの DDC 入力切替のみ
- **watchdog（Phase 4.3）**: BetterDisplay の論理接続/切断のみ
- 切替スクリプトが入力を変える → 次の watchdog ポーリングで各 Mac が自動追従

この設計により、切替スクリプト側で相手 Mac を直接操作する必要がなくなり、SSH なしでも両 Mac の状態が整合する。

### 4.4 Hammerspoon 設定

`~/.hammerspoon/init.lua`:

```lua
-- F20 = M2 Max をメインに
hs.hotkey.bind({}, "F20", function()
  local output, status = hs.execute(os.getenv("HOME") .. "/scripts/switch-to-m2max.sh")
  if not status then
    hs.alert.show("Switch to M2 Max FAILED")
  end
end)

-- F21 = M3 Air をメインに
hs.hotkey.bind({}, "F21", function()
  local output, status = hs.execute(os.getenv("HOME") .. "/scripts/switch-to-m3air.sh")
  if not status then
    hs.alert.show("Switch to M3 Air FAILED")
  end
end)
```

**両 Mac でこの設定を行う**こと。Corne が KVM で切り替わった先でも同じキーが効くようにするため。

Hammerspoon をリロード:
```bash
hs -c "hs.reload()"
```

---

## Phase 5: Corne Vial キーマップ

Vial で Adjust レイヤーに F20 / F21 を割り当てる。ビルドやフラッシュは不要で、GUI 上の操作が即座にファームへ反映される。

### 5.1 手順

1. **Vial を起動**し、Corne を USB で接続して認識させる
2. 左側のレイヤー選択で **Adjust レイヤー**（通常 Layer 3）を選ぶ
3. 右側のキーコード選択エリアで **Function** カテゴリ、または検索ボックスに `F20` と入力
4. 配置したいキー位置（例：左手中指・薬指あたり）をクリック → `F20` をクリックして割り当て
5. 同様に隣のキーに `F21` を割り当て
6. 自動保存されるので、そのまま Adjust レイヤーに入って F20 / F21 を押せば動作テスト可能

配置イメージ：

```
┌─ Adjust レイヤー ─────────────────────────────┐
│ ___  ___  ___  ___  ___  ___    ___  ___ ... │
│ ___  F20  F21  ___  ___  ___    ___  ___ ... │
│ ___  ___  ___  ___  ___  ___    ___  ___ ... │
│           ___  ___  ___    ___  ___  ___     │
└──────────────────────────────────────────────┘
```

### 5.2 バックアップ

変更後、Vial の「Save Current Layout」から `.vil` ファイルを書き出してバックアップする。別 Mac で Vial を使う場合もこのファイルから「Load saved layout」で復元可能。

### 5.3 動作確認

F20 / F21 を押下して、Hammerspoon のアラート通知（または切替スクリプトの通知）が出ることを確認する。出ない場合は以下を確認：

- Karabiner EventViewer（macOS）で F20 / F21 のキーコードが実際に飛んでいるか
- Hammerspoon のコンソールでホットキーが登録されているか（`hs.hotkey.bind` がエラーなく実行されているか）
- Adjust レイヤーに正しく入れているか（Vial のレイヤー切替キーを押してから F20 を押す必要がある）

**補足**: Vial 対応ファームが書き込まれている前提の手順です。既に Vial で操作できているなら当然対応済みなので問題ありません。QMK のソースコード管理は不要で、Vial 上の変更は `.vil` ファイルでのみ管理されます。

---

## Phase 6: M3 Air クラムシェル常時稼働設定

### 6.1 スリープ抑止

```bash
# システム全体のスリープを無効化（要 sudo）
sudo pmset -a sleep 0
sudo pmset -a disksleep 0
sudo pmset -a displaysleep 30
sudo pmset -a networkoversleep 1
sudo pmset -a tcpkeepalive 1
sudo pmset -a womp 1
sudo pmset -a autorestart 1

# 確認
pmset -g
```

### 6.2 caffeinate を LaunchAgent で常時起動

`~/Library/LaunchAgents/com.yap.caffeinate.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.yap.caffeinate</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/caffeinate</string>
    <string>-dimsu</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
```

ロード:
```bash
launchctl load ~/Library/LaunchAgents/com.yap.caffeinate.plist
```

### 6.3 クラムシェル成立条件の確認

M3 Air の蓋を閉じる前に以下を確認:

- [ ] BenQ から Thunderbolt 4 経由で給電が来ている（メニューバーの電池アイコンが充電中表示、96W 供給なら余裕）
- [ ] BenQ に M3 Air の映像が出力されている
- [ ] 外部キーボード（Corne が BenQ USB ハブ経由）または外部マウス（MX Ergo の Bluetooth）が接続されている
- [ ] `pmset -g` で sleep 0 が有効

クラムシェル: 蓋を静かに閉じる → 外部画面の表示が維持されれば成立。

### 6.4 Wi-Fi 安定化

ルーター側で M3 Air に固定 IP を割り当てておくとネットワーク経由のジョブが安定する。

---

## Phase 7: 動作テスト

### 7.1 単体テスト

- [ ] m1ddc から iiyama の入力切替が効く
- [ ] m1ddc から BenQ の入力切替が効く
- [ ] BenQ の PBP が On になっていて左右に別ソースが表示される
- [ ] BenQ の KVM が映像切替に連動して Corne のホストを切り替える
- [ ] `betterdisplaycli set --name X --disconnected=true/false` が両 Mac で効く
- [ ] display-watchdog.sh を手動実行すると入力に応じて接続/切断が切り替わる
- [ ] launchd 経由で display-watchdog が常駐している（`launchctl list | grep watchdog`）
- [ ] Hammerspoon F20 / F21 がそれぞれスクリプトを実行する
- [ ] Corne の Adjust レイヤーから F20 / F21 が発行されている（Karabiner EventViewer で確認）

### 7.2 結合テスト

- [ ] Corne の F20 → M2 Max がメイン、M3 Air は BenQ の PBP 片側に表示
- [ ] Corne の F21 → M3 Air がメイン、M2 Max は BenQ の PBP 片側に表示
- [ ] 切替後、Corne のキー入力が切替後の Mac に行く
- [ ] MX Ergo のホストボタンでマウスも連動切替可能
- [ ] 非アクティブ側 Mac のクラムシェル維持
- [ ] watchdog により、切替後 4〜5 秒以内に非アクティブ側 Mac でモニタが論理切断される（幽霊スペースが出ない）
- [ ] watchdog により、切替後 4〜5 秒以内にアクティブ側 Mac でモニタが論理接続される
- [ ] 物理 OSD ボタンで入力切替しても watchdog が追従する
- [ ] Claude Code スケジュールジョブが両 Mac で常時稼働

### 7.3 初期不良チェック（購入後 2 週間以内）

BenQ の初期不良交換期間は通常 2 週間。以下を毎日軽く確認：

- [ ] ドット抜け、バックライトムラ
- [ ] 発色の偏り、色ムラ
- [ ] KVM 切替の信頼性（10 回連続で切替テスト）
- [ ] PBP の描画が安定しているか
- [ ] スリープ復帰時の入力検出
- [ ] ファンノイズ・発熱
- [ ] ケーブル抜き差しでの再認識

問題なければ Phase 2（2 枚目購入、iiyama 置き換え）に進む。

---

## トラブルシューティング

### m1ddc が iiyama / BenQ を認識しない
- 各モニタの OSD で DDC/CI を明示的に ON
- ケーブルが DP Alt Mode + USB 2.0 以上をサポートしているか確認（安価な HDMI/USB-C ケーブルは DDC が通らないことがある）
- `m1ddc display list` の出力で UUID を正確に控える（ディスプレイ名指定は m1ddc では使えないため UUID を使う）
- BenQ PD2730S は PBP オン/オフで UUID が変わるため、PBP 切替後に `m1ddc display list` を再確認

### BenQ の KVM が切り替わらない
- OSD の KVM メニューで「映像入力連動」が On か確認
- USB 上流ケーブル（TB4 と USB-B/USB-C の両方）が物理的に繋がっているか
- BenQ Display Pilot 2 でファームウェアを最新に更新
- PD2730S / MA270S は MST + KVM の同時有効化で問題が出た報告あり → MST は Off に

### PBP 中に `set input` するとレイアウトが崩れる
- PBP On 時と Off 時で DDC の振る舞いが異なる場合がある
- 回避策: `set pbp off` → `set input X` → `set pbp on` の順で発行、または KVM のみ切り替える DDC コマンドを使う
- 最悪の場合は PBP を諦めて単画面運用、M2 Max/M3 Air でアクティブな方だけを BenQ に出す

### 切替後に Corne が反応しない
- USB ハブの再列挙に 1〜2 秒かかる、少し待つ
- 反応がない場合は BenQ の KVM 上流割当設定を確認
- Corne 側が USB 2.0 Hub として正しく認識されているか System Information で確認

### M3 Air が蓋を閉じるとスリープする
- クラムシェル成立条件（電源・ディスプレイ・キーボード/マウス）のいずれかが満たされていない
- TB4 ケーブルが 96W PD 対応の認証品か確認（安物は PD が通らないことがある）
- System Settings > Battery > Options > "Prevent automatic sleeping on power adapter" を ON

### Claude Code ジョブが夜間に停止する
- `pmset -g assertions` でスリープ抑止状態を確認
- `launchctl list | grep caffeinate` で LaunchAgent が起動しているか確認
- ルーターとの Wi-Fi リンクが維持されているか、別端末から ping で確認

### BenQ の発色が気に入らない
- MA270S の場合は M-book モードを On
- PD2730S の場合は Display P3 プリセットを選択
- BenQ Display Pilot 2 でキャリブレーションプロファイル適用

---

## 参考リンク

- m1ddc: https://github.com/waydabber/m1ddc
- Hammerspoon: https://www.hammerspoon.org/
- Vial: https://get.vial.today/
- BenQ MA270S 公式: https://www.benq.com/en-us/monitor/home/ma270s.html
- BenQ PD2730S 公式: https://www.benq.com/en-us/monitor/creative-pro/pd2730s.html
- BenQ Display Pilot 2: https://www.benq.com/en-us/support/downloads-faq/software/display-pilot-2.html

---

## 作業の進め方（推奨順序）

1. **購入前**: Phase 1（m1ddc、Hammerspoon、QMK 環境の準備）をすべて先に済ませる
2. **実機到着当日**: Phase 2（設置）→ Phase 3（OSD 設定）→ Phase 4.1（DDC コード特定）まで
3. **翌日以降**: Phase 4.2〜4.3（スクリプトと Hammerspoon）→ Phase 5（Vial でキーマップ設定）→ Phase 6（クラムシェル）
4. **全体が動いたら**: Phase 7.1〜7.2 の動作テスト
5. **2 週間観察**: Phase 7.3 の初期不良チェック
6. **問題なければ Phase 2 の検討**: iiyama を BenQ もう 1 枚に置き換え、トポロジーを左右対称化

各 Phase で詰まったらトラブルシューティングを参照。実機到着後に DDC コード値が典型値と異なる場合は、その時点でメモを取ってスクリプトに反映する。
