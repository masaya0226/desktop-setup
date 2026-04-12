# デスクトップ環境セットアップ：引き継ぎ資料

Claude Code での作業継続用に、これまでの議論と決定事項をまとめたもの。

---

## 1. プロジェクト概要

### 目標
2台の Mac（M2 Max MacBook Pro 14" / M3 MacBook Air）を、Corne Cherry キーボードのワンキーで切り替えられる常時稼働デスクトップ環境を構築する。

### 要件
- USB-C ケーブルの抜き差しをやめる
- 両 Mac で Claude Code のスケジュールジョブを常時実行
- Corne のワンキー（F20/F21）でモニタ入力 + KVM + キーボードホストを一括切替
- M3 Air はクラムシェル常時稼働
- M2 Max は会社 PC（SSH 受け入れ不可）

---

## 2. ハードウェア構成

### 確定済み
| 機器 | 役割 | 状態 |
|---|---|---|
| M2 Max MacBook Pro 14" | メイン Mac（会社 PC） | 既存 |
| M3 MacBook Air | サブ Mac（私用） | 既存 |
| Corne Cherry（Vial 管理） | 分割キーボード | 既存 |
| MX Ergo | マウス（Bluetooth 3 ペアリング） | 既存 |
| iiyama XUB2792QSN (PL2792QN) | Main モニタ 27" WQHD | 既存 |
| **BenQ PD2730S** | **Sub モニタ 27" 5K（KVM + PBP）** | **購入済み** |

### Phase 2（将来）
iiyama を BenQ もう 1 枚（PD2730S or MA270S）に置き換える。

### 接続トポロジー
```
                 iiyama PL2792QN (Main)
                   ├── USB-C(TYPEC) ── M2 Max
                   └── USB-C(TYPEC) ── M3 Air（入力値 19）

                 BenQ PD2730S (Sub, PBP 左右分割)
                   ├── Thunderbolt 4 ── M3 Air    (映像 + 96W 給電 + USB、KVM 上流 A)
                   ├── HDMI 2.1 ─────── M2 Max    (映像のみ)
                   └── USB-C/USB-B ──── M2 Max    (KVM 上流 B、データのみ)

                 BenQ USB ハブ背面
                   └── Corne キーボード
```

---

## 3. 確認済み技術情報

### m1ddc
- ディスプレイ指定は **UUID のみ**（名前指定は不可、番号は接続順で変わる）
- UUID は **Mac ごとに異なる**（同じモニタでも M2 Max と M3 Air で別 UUID）
- BenQ PD2730S は **PBP オン/オフで別 UUID** になる

### M3 Air 側の確認済み値

| ディスプレイ | モード | UUID | 入力値 |
|---|---|---|---|
| BenQ PD2730S | PBP オフ | `2DF75969-A2F5-4608-A9B4-429B3A3CA4BB` | TB=21, HDMI=17 |
| BenQ PD2730S | PBP オン | `4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20` | TB=21, HDMI=17 |
| iiyama PL2792QN | — | `180CEA86-E5B7-4FC4-B2D6-5BFC6C9D81B5` | HDMI=17, TYPEC=19 |

- M3 Air → iiyama: TYPEC 接続（入力値 19）
- M3 Air → BenQ: Thunderbolt 接続（入力値 21）

### M2 Max 側（未確認）
- UUID: 未取得（`m1ddc display list` を M2 Max で実行が必要）
- M2 Max → iiyama: USB-C 接続（入力値は要確認）
- M2 Max → BenQ: HDMI 接続（入力値はおそらく 17）

### BetterDisplay
- PD2730S の PBP モードでは EDID が 2560×1440（16:9）として報告される
- 実際の物理パネル半分は 2560×2880（縦長）
- BetterDisplay で以下を設定することで正しく縦長 Retina 表示される：
  - **システム構成を編集**: オン
  - **フレキシブルサイズ調整**: オン
  - **カスタムスケール解像度**: オン（2560×2880 LoDPI + 1280×1440 HiDPI を登録）
  - **パネルのネイティブピクセル解像度を編集**: オン（値: **2560×2880**）
  - **デフォルトの解像度を編集**: オン（1280×1440 HiDPI @ 60Hz）
- PBP オフ時は BetterDisplay 設定不要（5120×2880 で macOS が自動的に Retina 化）
- PBP オン/オフで BetterDisplay からは別ディスプレイとして認識される
- BetterDisplay Pro には「信号喪失時の自動切断」トグルは存在しなかった → watchdog 方式で対応

### Display Pilot 2（BenQ 公式ツール）
- PBP オン/オフメニューがある（GUI 上で確認済み）
- ショートカットキー割り当て、CLI インターフェースの有無は未確認
- DDC/CI 経由での PBP 制御（メーカー固有 VCP コード）も未調査

### KVM
- BenQ PD2730S は KVM 搭載
- TB4 側（M3 Air）と USB-C/USB-B 側（M2 Max）の 2 上流を持つ
- 映像入力連動で USB ハブ（Corne 接続先）を自動切替

---

## 4. ソフトウェアスタック

| ツール | 用途 | 状態 |
|---|---|---|
| m1ddc | DDC/CI 経由でモニタ入力切替 | M3 Air にインストール済み |
| BetterDisplay Pro | PBP 時の縦長 HiDPI 解像度、論理接続/切断 | M3 Air にインストール済み（Pro 課金状況は要確認） |
| Hammerspoon | F20/F21 ホットキーから切替スクリプトを実行 | M3 Air にインストール済み |
| Vial | Corne のキーマップ管理 | 既存 |
| Display Pilot 2 | BenQ モニタ制御（PBP 切替の可能性あり） | インストール済み |
| caffeinate + launchd | M3 Air のスリープ抑止 | 未設定 |

---

## 5. アーキテクチャ設計

### 責務分離

```
[Corne F20/F21]
    │
    ▼
[Hammerspoon] ── ホットキーキャプチャ
    │
    ▼
[切替スクリプト] ── m1ddc で DDC 入力切替のみ
    │
    ▼
[BenQ KVM] ── 映像入力連動で Corne の USB ホスト切替（ハードウェア側）
    │
    ▼
[display-watchdog] ── 常駐。4秒間隔で m1ddc ポーリング
    │                   → アクティブ入力が自分なら betterdisplaycli --disconnected=false
    │                   → アクティブ入力が自分でなければ betterdisplaycli --disconnected=true
    ▼
[BetterDisplay] ── 論理接続/切断で幽霊スペース問題を解消
```

### watchdog 方式を採用した理由
- M2 Max は会社 PC のため M3 Air から SSH できない
- 各 Mac が独立して動作する必要がある
- DDC ポーリングで「今モニタが自分を映しているか」を判定し、自律的に接続/切断

---

## 6. 未完了タスク

### 優先度高（セットアップ完了に必須）

- [ ] **M2 Max 側で `m1ddc display list` を実行**して UUID と入力値を確定
- [ ] **M2 Max に m1ddc, BetterDisplay, Hammerspoon をインストール**
- [ ] **M2 Max 側の BetterDisplay PBP 設定**（M3 Air と同じ手順）
- [ ] **切替スクリプトを M2 Max 用に作成**（UUID と入力値を埋める）
- [ ] **watchdog スクリプトを M2 Max 用に作成**
- [ ] **切替スクリプトの動作テスト**（m1ddc で入力切替が効くか）
- [ ] **BenQ KVM の動作確認**（入力切替で Corne のホストが切り替わるか）
- [ ] **Hammerspoon の F20/F21 設定**（両 Mac で）
- [ ] **Vial で Corne の Adjust レイヤーに F20/F21 配置**
- [ ] **watchdog の launchd 設定と動作テスト**（両 Mac で）
- [ ] **M3 Air のクラムシェル常時稼働設定**（pmset, caffeinate, LaunchAgent）

### 優先度中（調査・改善）

- [ ] **Display Pilot 2 の CLI / ショートカット対応確認**（PBP 切替のスクリプト化）
- [ ] **DDC VCP コード調査**（PBP オン/オフの制御コード特定）
- [ ] **betterdisplaycli の `--name` 指定**が PBP オン/オフで同じ名前で動くか確認
- [ ] **watchdog の BenQ UUID 問題**：PBP オン/オフで UUID が変わるため、watchdog が正しく動くか検証
- [ ] **BetterDisplay Pro のライセンス確認**（betterdisplaycli が使えるか）

### 優先度低（Phase 2）

- [ ] iiyama を BenQ もう 1 枚に置き換え
- [ ] 接続トポロジーの左右対称化
- [ ] Thunderbolt 4 ドックの導入検討（ケーブル本数削減）

---

## 7. 既知の問題・注意点

### PBP 時の解像度問題（解決済み）
- PD2730S は PBP 時に EDID を 2560×1440 として報告する
- BetterDisplay で「パネルのネイティブピクセル解像度を編集」を 2560×2880 に設定することで解決
- PBP オフ時は設定不要

### 入力切替時の幽霊スペース問題（watchdog で対応予定）
- モニタの入力を切り替えても Mac 側はモニタを認識し続ける
- BetterDisplay の論理切断で対応する設計
- BetterDisplay に「信号喪失時の自動切断」機能はなかった
- watchdog ポーリング方式（4 秒間隔）で代替

### PBP オン/オフでの UUID 変化
- BenQ PD2730S は PBP モード切替で別 UUID になる
- 常用は PBP オン（UUID: 4B3EC4EE-...）
- watchdog / 切替スクリプトは PBP オン時の UUID を使う前提
- PBP をスクリプトから切り替える場合は UUID の動的取得が必要

### M2 Max が会社 PC
- M3 Air から M2 Max への SSH は不可
- watchdog 方式（各 Mac が独立動作）で対応
- M2 Max のセキュリティポリシーで Homebrew / BetterDisplay 等のインストールに制約がある可能性

---

## 8. 参考リンク

- m1ddc: https://github.com/waydabber/m1ddc
- BetterDisplay: https://github.com/waydabber/BetterDisplay
- Hammerspoon: https://www.hammerspoon.org/
- Vial: https://get.vial.today/
- BenQ PD2730S 公式: https://www.benq.com/en-us/monitor/creative-pro/pd2730s.html
- BenQ Display Pilot 2: https://www.benq.com/en-us/support/downloads-faq/software/display-pilot-2.html

---

## 9. 関連ファイル

- **セットアップ手順書**: `desktop-setup-guide.md`（同ディレクトリ）
  - Phase 0〜7 の全手順を記載
  - 切替スクリプト、watchdog、Hammerspoon、Vial、クラムシェル設定を含む
  - M3 Air 側の UUID・入力値は反映済み、M2 Max 側は要確認のプレースホルダあり

---

## 10. 次にやるべきこと

1. M2 Max で `brew install m1ddc` → `m1ddc display list` で UUID と入力値を確定
2. M2 Max に BetterDisplay Pro をインストールし PBP 時の解像度設定
3. 両 Mac で切替スクリプトの動作テスト
4. KVM が映像連動で動くか確認
5. watchdog を仕込んで幽霊スペース問題の解消を確認
6. Hammerspoon + Vial を設定して Corne ワンキー切替を完成
7. M3 Air のクラムシェル常時稼働設定
8. Display Pilot 2 の CLI/ショートカット調査（PBP スクリプト制御）
