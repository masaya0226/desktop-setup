# ディスプレイ切替設計書

## 構成概要

BenQ PD2730S x2 + Mac x2（M2 Max / M3 Air）の構成。
物理配置: `[Sub(左)] [Main(右)]`

- **メインモニタ（右）**: PD2730S（旧BenQ）。PBPなし。macOS 主ディスプレイ。
- **サブモニタ（左）**: PD2730S（新規購入）。PBP使用。KVM はこちら経由（物理切替）。

## 状態定義

| 状態 | Main(右) | Sub PBP | Sub映像 | 画面の見え方 |
|---|---|---|---|---|
| **S1** | Max | On | 左=Air 右=Max | `[Air│Max] [Max]` |
| **S3** | Air | On | 左=Max 右=Air | `[Max│Air] [Air]` |
| **S7** | Max | Off | Max | `[Max] [Max]` |
| **S9** | Air | Off | Air | `[Air] [Air]` |

原則: PBPオン時は **メインPCがSub右側(0x7E)** に表示される（物理配置 `[Sub] [Main]` で画面が連続するように）。

KVM（Corne接続先）は物理スイッチで切替。

---

## ショートカットキー設計

### Key2: メイン入替（トグル、1キー）

PBPオン/オフどちらでも「メインPCを入れ替える」。

| 遷移 | 操作内容 |
|---|---|
| S1→S3 | Main入力→Air, Sub左右入替, 主ディスプレイ設定 |
| S3→S1 | Main入力→Max, Sub左右入替, 主ディスプレイ設定 |
| S7→S9 | Main入力→Air, Sub入力→Air, 主ディスプレイ設定 |
| S9→S7 | Main入力→Max, Sub入力→Max, 主ディスプレイ設定 |

**トグル判定**: メインモニタの 0x60 を `BetterDisplay get` で取得し、Max/Air を判定。

### Key3: PBP切替（トグル、1キー）

| 遷移 | 操作内容 |
|---|---|
| S1→S7 | PBPオフ |
| S3→S9 | PBPオフ |
| S7→S1 | PBPオン |
| S9→S3 | PBPオン |

**トグル判定**: サブモニタの VCP 0x7D を取得（0=オフ, 2=PBPオン）。

入力設定(0x60, 0x7E)は PBP 切替で維持されるため 0x7D のみ操作する。

---

## 状態遷移図

```
     Key2(入替)
S1 ←————————→ S3
↕ Key3(PBP)    ↕ Key3(PBP)
S7 ←————————→ S9
     Key2(入替)
```

全4状態が2キーで到達可能。

---

## DDC VCP コード一覧（BenQ PD2730S）

### 確認済み制御コード

| VCPコード | 用途 | 値 | 読み取り | 書き込み |
|---|---|---|---|---|
| **0x60** | **入力ソース（メイン/PBP左）** | 17=HDMI, 21=TB, 15=DP | ✅ | ✅ |
| **0x7D** | **PBPモード** | 0=オフ, 2=PBPオン | ✅ | ✅ |
| **0x7E** | **PBPサブ入力（PBP右）** | 17=HDMI, 21=TB, 15=DP | ✅ | ✅ |
| 0x7F | 0x7Eの読み取り専用ミラー | 0x7Eと同値 | ✅ | ❌ |

### KVM制御について

- KVM は物理スイッチで切替（DDC 連動は使用しない）
- DDC (VCP) では KVM を直接制御できない（全 0x00〜0xFF の VCP コードを KVM 切替前後でダンプし diff を取ったが差分ゼロ）
- KVM は BenQ 内部の USB ハブスイッチングであり、DDC のディスプレイ制御レイヤーとは独立
- **調査予定**: PBP右側(0x7E)を KVM 連動にできないか調査（OSD設定 or DDC で PBP swap 機能の有無）

### DDC 操作の注意点

- **連続書き込みには sleep 1 が必要**（間隔が短いと2つ目が無視される）
- **PBPオン/オフでUUIDが変わる可能性あり**（旧BenQで確認済み。新サブモニタでも要確認）
- DDC書き込みは BetterDisplay CLI 経由: `/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay`
- 2台の PD2730S は同一モデル名のため **UUID で識別**する（`-name=` ではなく `-uuid=`）
- m1ddc の `set pbp` / `set pbp-input` はBenQでは効かない（Dell向け実装）
- **PBP切替直後は DDC が不安定**（数秒待つ必要あり）
- **PBP切替で 0x60, 0x7E の値は維持される**（入力設定の再送不要）

### PBP左右入替の手順（サブモニタ）

**重要**: 0x7E（右/サブ側）を先に変更してから 0x60（左/メイン側）を切替する。

```bash
BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# 例: 左=Air,右=Max → 左=Max,右=Air に入替
$BD set -uuid="$SUB_UUID" -ddc -vcp=0x7E -value=$SUB_AIR   # 右をAirに
sleep 1
$BD set -uuid="$SUB_UUID" -ddc -vcp=0x60 -value=$SUB_MAX   # 左をMaxに
```

---

## BetterDisplay 論理接続/切断（幽霊スペース対策）

### 幽霊スペースが問題になるケース

**PBPオン時の、サブ側（非メイン）Mac のメインモニタのみ。**

- S1: M3 Air がメインモニタを映していない → M3 Air で幽霊スペース
- S3: M2 Max がメインモニタを映していない → M2 Max で幽霊スペース
- S7/S9: 映していない側の Mac は操作しないので問題なし
- サブモニタ: PBPオン時は両方映しているので幽霊にならない

### 役割分担

| 担当 | 役割 |
|---|---|
| **switch-main.sh** | DDC で入力切替 + 自分のメインモニタを `connected=on/off`（即座に対応）+ 主ディスプレイ設定 |
| **switch-pbp.sh** | PBP 切替のみ。メインモニタの connected は触らない（DDC が不安定なため） |
| **display-watchdog.sh** | サブモニタの状態を見てメインモニタの connected を補完管理 |

### watchdog の仕様

サブモニタは常に `connected=on` なので DDC 読み取り可能。サブモニタの PBP 状態と入力からメインモニタのあるべき状態を判定。

```
PBPオン かつ Sub左(0x60)=自分 → 自分はサブ側 → メインモニタ=off
PBPオン かつ Sub左(0x60)≠自分 → 自分がメイン → メインモニタ=on
PBPオフ → メインモニタは触らない（操作しないので問題なし）
状態変化時のみ操作（リソース節約）
```

### BetterDisplay connected の制約

- `connected=off` にすると BetterDisplay DDC ともに読み書き不可
- `connected=on` に戻せば DDC 復旧
- switch-main.sh はメインモニタが `connected=off` の場合、一時的に `on` にして DDC 読み取り後に判定

### コマンド

```bash
BD="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"

# 論理切断/接続 (UUID で指定)
$BD set -uuid="$MAIN_UUID" -connected=off
$BD set -uuid="$MAIN_UUID" -connected=on

# 状態確認
$BD get -uuid="$MAIN_UUID" -connected
```

---

## 主ディスプレイ設定

切替後にメインモニタ（右）を macOS の主ディスプレイに設定する。`displayplacer` を使用。

```bash
# インストール
brew install displayplacer

# 現在の設定確認
displayplacer list

# 主ディスプレイ設定 (ID は displayplacer list で確認)
# displayplacer "id:<MAIN_MONITOR_ID> origin:(0,0)"
```

---

## 接続構成

| 接続 | ケーブル | 入力値 (0x60) |
|---|---|---|
| M3 Air → メインモニタ | Thunderbolt | 21 (TB) |
| M2 Max → メインモニタ | HDMI | 17 (HDMI) |
| M3 Air → サブモニタ | Thunderbolt | 21 (TB) |
| M2 Max → サブモニタ | DisplayPort | 15 (DP) |

## UUID 一覧

| ディスプレイ | モード | M3 Air UUID | M2 Max UUID |
|---|---|---|---|
| メインモニタ | — | `2DF75969-A2F5-4608-A9B4-429B3A3CA4BB` | `7A782274-C5F3-414C-B90A-41770749B121` |
| サブモニタ | PBP オフ | `B02476A6-81D7-444F-B03B-DC515516025A` | `4A8F5105-1777-4D51-8E49-ECDD133C3D7B` |
| サブモニタ | PBP オン | `4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20` | `C2E62FA2-0938-463E-92B2-FD77960B47C5` |

サブモニタは PBP のオン/オフで UUID が変わるため、スクリプトでは両UUIDを試行するヘルパー関数 (`sub_get` / `sub_set`) を使う。

---

## スクリプト

| ファイル | 機能 | テスト状況 |
|---|---|---|
| `scripts/m3air/switch-main.sh` / `scripts/m2max/switch-main.sh` | Key2: メイン入替 + メインモニタ connected 管理 + 主ディスプレイ設定 | 未テスト |
| `scripts/m3air/switch-pbp.sh` / `scripts/m2max/switch-pbp.sh` | Key3: PBP切替のみ | 未テスト |
| `scripts/m3air/display-watchdog.sh` / `scripts/m2max/display-watchdog.sh` | サブモニタを見てメインモニタ connected を補完管理 | 未テスト |

両 Mac 用に分離。UUID・入力値は各スクリプト先頭で確定済み。

---

## 未完了タスク

### 初期セットアップ

- [x] ケーブル接続方式の確定と入力値の確認
- [x] 2台の PD2730S の UUID 確認（PBPオン/オフ両方）
- [x] スクリプトに実値を反映
- [ ] displayplacer のインストールとモニタ ID 確認 (`brew install displayplacer` → `displayplacer list`)
- [ ] switch-main.sh の displayplacer コマンドを有効化
- [ ] PBP右側(0x7E)の KVM 連動可否を調査（OSD設定 / DDC PBP swap）

### テスト

- [ ] S1↔S3 (switch-main.sh、PBPオン時のメイン入替)
- [ ] S1↔S7 (switch-pbp.sh、M2 Max がメインの状態)
- [ ] S3↔S9 (switch-pbp.sh、M3 Air がメインの状態)
- [ ] S7↔S9 (switch-main.sh、PBPオフ時のメイン入替)
- [ ] display-watchdog.sh の動作テスト
- [ ] 主ディスプレイがメインモニタに固定されることの確認
- [ ] M2 Max 側からの実行テスト

### 実装

- [ ] Hammerspoon 設定（F20/F21 → スクリプト実行）
- [ ] Vial で Corne の Adjust レイヤーに F20/F21 配置
- [ ] display-watchdog.sh の launchd 常駐設定
- [ ] M2 Max 用スクリプト作成（UUID・入力値変更のみ）
- [ ] M2 Max に BetterDisplay, Hammerspoon, displayplacer インストール
