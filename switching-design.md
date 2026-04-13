# ディスプレイ切替設計書

## 用語定義

| 用語 | 意味 |
|---|---|
| **メインモニタ** | 物理配置で右側のモニタ（PD2730S、PBPなし）。 |
| **サブモニタ** | 物理配置で左側のモニタ（PD2730S、PBP使用）。 |
| **主ディスプレイ** | macOS の「メインディスプレイ」設定。メインPC 側でメインモニタを主ディスプレイにする (`BetterDisplay -main=on`)。 |
| **メインPC** | 現在 Corne で操作中の Mac。メインモニタに表示される PC。 |
| **他PC** | メインPC ではない Mac。PBPオン時のみサブモニタ左半分に表示。 |

## 構成概要

BenQ PD2730S x2 + Mac x2（M2 Max / M3 Air）。物理配置: `[サブモニタ(左)] [メインモニタ(右)]`。KVM（Corne接続先）は物理スイッチで切替。

## 状態定義

| 状態 | Main(右) | Sub PBP | Sub映像 | 画面の見え方 |
|---|---|---|---|---|
| **S1** | Max | On | 左=Air 右=Max | `[Air│Max] [Max]` |
| **S3** | Air | On | 左=Max 右=Air | `[Max│Air] [Air]` |
| **S7** | Max | Off | Max | `[Max] [Max]` |
| **S9** | Air | Off | Air | `[Air] [Air]` |

原則: PBPオン時は **メインPCがSub右側(0x7E)** に表示される（物理配置 `[Sub] [Main]` で画面が連続するように）。

## ショートカットキー設計

### Key2 (F19): メイン入替

PBPオン/オフどちらでも「メインPCを入れ替える」。メインモニタの 0x60 を読んでトグル判定。

| 遷移 | 操作 |
|---|---|
| S1↔S3 | Main 0x60 切替 + Sub 左右入替 (PBP on 分岐) |
| S7↔S9 | Main 0x60 切替 + Sub 0x60 のみ切替 (PBP off 分岐、0x7E は触らない) |

### Key3 (F20): PBP 切替

サブモニタの 0x7D を読んでトグル判定。

| 遷移 | 操作 |
|---|---|
| S1↔S7 / S3↔S9 | Sub 0x7D 書込。off→on 時は 0x7E=メインPC / 0x60=他PC を追加で書き直し。 |

### 状態遷移図

```
     Key2(入替)
S1 ←————————→ S3
↕ Key3(PBP)    ↕ Key3(PBP)
S7 ←————————→ S9
     Key2(入替)
```

---

## DDC VCP コード一覧（BenQ PD2730S）

| VCP | 用途 | 値 | R | W |
|---|---|---|---|---|
| 0x60 | 入力ソース（メイン / PBP左） | 17=HDMI, 21=TB, 15=DP | ✅ | ✅ |
| 0x7D | PBP モード | 0=オフ, 2=PBPオン | ✅ | ✅ |
| 0x7E | PBPサブ入力（PBP右） | 17=HDMI, 21=TB, 15=DP | ✅ | ✅* |
| 0x7F | 0x7Eの読み取り専用ミラー | 0x7Eと同値 | ✅ | ❌ |

\* **PBP オフ時の 0x7E 書き込みは silent drop される** (後述)。

### DDC 操作の注意点

- **PBP オフ時、0x7E への書き込みは BenQ に silent drop される**（exit=0 stderr空 の見かけ成功を返すが値は変わらない）。PBP オン遷移時に 0x7E を書き直す設計にすること。
- **連続書き込みには sleep 1 が必要**（間隔が短いと無視される）。`sub_set_verified` が read-back 検証 + リトライでカバー。
- **PBP 切替直後は DDC が不安定**。`main_get_input` は空値時に最大 5 回リトライ。
- **PBP オン/オフでサブモニタの UUID が変わる**。`sub_get` / `sub_set` は両 UUID を試行する。
- **PBP 切替で 0x60, 0x7E の値は維持される**。
- **2台の PD2730S は同一モデル名**のため UUID で識別する（`-uuid=` 必須）。
- **m1ddc の `set pbp` / `set pbp-input` は BenQ では効かない**（Dell 向け実装）。BetterDisplay CLI で任意 VCP を叩く。
- **KVM は物理スイッチ経由**。DDC 制御不可（全 VCP を KVM 切替前後でダンプし diff ゼロ確認済み）。

---

## BetterDisplay 論理接続/切断（幽霊スペース対策）

**対策が必要なケース**: PBPオン時、サブ側（非メイン）Mac のメインモニタ。

- S1: M3 Air がメインモニタを映していない → M3 Air で幽霊スペース → `connected=off`
- S3: M2 Max がメインモニタを映していない → M2 Max で幽霊スペース → `connected=off`
- S7/S9: 非メイン PC は操作しないため問題なし

### 役割分担

| 担当 | 役割 |
|---|---|
| `switch-main.sh` | DDC 入力切替 + 自分のメインモニタ `connected=on/off` + 主ディスプレイ設定 |
| `switch-pbp.sh` | PBP 切替のみ。connected は触らない |
| `display-watchdog.sh` | サブモニタの状態を見てメインモニタ connected を補完管理 (launchd 常駐) |

### watchdog の判定ロジック

Sub 0x60 は PBP on では「サブ左の入力」、PBP off では「サブ全体の入力」= 現在 active な PC を示す。両モードで `Sub 0x60 == 自分の入力値` を判定材料に使える。

```
PBPオン:
  Sub 0x60 = 自分 → 自分はサブ左 (メインは他PC) → connected=off
  Sub 0x60 ≠ 自分 → 自分がメイン → connected=on

PBPオフ:
  Sub 0x60 = 自分 → 自分が active PC (メインモニタにも自分) → connected=on
  Sub 0x60 ≠ 自分 → 他PC が active → connected=off
```

> 旧設計では PBP オフ時を「触らない」としていたが、非メイン PC 側の `connected=off` が別状態へ移行した後も残留するケースがあり、メインモニタが真っ暗になる不具合が起きた。PBP オフ時も sub 0x60 を信頼して判定するよう修正。

### watchdog と切替スクリプトの相互排他

Key2/Key3 の実行中に watchdog が DDC の中間状態を読んで connected を誤上書きするレースを防ぐため、**ロックファイル `/tmp/desktop-switcher.lock`** による相互排他を実装。

- 切替スクリプト: 起動時に lock 作成、`trap EXIT` で 2 秒 sleep 後に削除 (DDC 物理反映待ち込み)
- watchdog: ループ先頭で lock 存在チェック、存在すればスキップ
- Stale 対策: 30 秒以上古いロックは watchdog 側で強制削除

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

---

## スクリプト

| ファイル | 機能 |
|---|---|
| `scripts/m3air/switch-main.sh` / `scripts/m2max/switch-main.sh` | Key2: メイン入替 + connected 管理 + 主ディスプレイ設定 |
| `scripts/m3air/switch-pbp.sh` / `scripts/m2max/switch-pbp.sh` | Key3: PBP 切替 |
| `scripts/m3air/display-watchdog.sh` / `scripts/m2max/display-watchdog.sh` | connected 補完 (launchd 常駐) |

両 Mac 用に分離。UUID・入力値・自分のメインPC識別は各スクリプト先頭で確定済み。

### ヘルパー関数

- `main_get_input` — メインモニタ 0x60 読み取り。空値時に最大 5 回リトライ。
- `main_set_input` — メインモニタ 0x60 書込。stderr "Failed." 検出時に最大 3 回リトライ。
- `sub_get` — サブモニタ DDC 読み取り。PBP on/off 両 UUID を試行。
- `sub_set` — サブモニタ DDC 書込。両 UUID を試行。
- `sub_set_verified` — `sub_set` + read-back 検証 + 最大 3 回リトライ。

## テスト状況

- [x] S1↔S3 / S7↔S9 (switch-main.sh、PBPオン/オフ時のメイン入替)
- [x] S1↔S7 / S3↔S9 (switch-pbp.sh、PBP on/off 切替)
- [x] switch-main.sh の主ディスプレイ維持 (BetterDisplay `-main=on`)
- [x] 0x7E silent drop 対策後の全 4 状態遷移
- [x] watchdog ロック排他動作 (ロック保持中は干渉しない、解放後 4-8s 以内に復旧)
- [ ] M2 Max 側からの実行テスト
- [ ] 長時間運用テスト

## 残タスク

- [ ] Vial で Corne の Adjust レイヤーに F19/F20 配置 (手動作業)
- [ ] M2 Max 側からの動作テスト
- [ ] 長時間運用テスト
- [ ] PBP 右側(0x7E) の KVM 連動可否調査 (OSD設定 / DDC PBP swap、余裕あれば)
