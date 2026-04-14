# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

2台の Mac（M2 Max MacBook Pro 14" / M3 MacBook Air）と 2台の BenQ PD2730S モニタを、Corne Cherry キーボードのショートカットキーで一括切替できる常時稼働デスクトップ環境。

## 用語定義

| 用語 | 意味 |
|---|---|
| **メインモニタ** | 物理配置で右側のモニタ。PBPなし。常に一つのPCのみを表示。 |
| **サブモニタ** | 物理配置で左側のモニタ。PBP機能を使い2つのPCを並置可能。 |
| **主ディスプレイ** | macOS の「メインディスプレイ」。メインPC 側でメインモニタを主ディスプレイにする。`BetterDisplay -main=on` で固定。 |
| **メインPC** | 現在 Corne キーボードで操作している側の Mac（物理 KVM で切替）。メインモニタに表示されている PC。 |
| **他PC** | メインPC ではない側の Mac。PBPオン時はサブモニタの左半分に表示。 |

## ファイル構成

- `switching-design.md` — 設計書（状態定義、DDC VCPコード、スクリプト仕様、トラブルシューティング）
- `m2max-setup.md` — M2 Max 側セットアップ手順書（clone, Hammerspoon, launchd, TCC対策）
- `scripts/m3air/` — M3 Air 用スクリプト（switch-main.sh, switch-pbp.sh, display-watchdog.sh）
- `scripts/m2max/` — M2 Max 用スクリプト（同上）

## アーキテクチャ

```
[Corne F19/F20] → [Hammerspoon] → [切替スクリプト]
                                     ├ BetterDisplay DDC: メインモニタ入力切替
                                     ├ BetterDisplay DDC: サブモニタ PBP/入力
                                     ├ BetterDisplay: メインモニタ connected 管理
                                     └ BetterDisplay -main=on: 主ディスプレイ設定
                                           ↓
                                     [display-watchdog (launchd)]
                                     サブモニタ状態を見てメインモニタ connected 補完
```

物理配置: `[Sub(左,PBP)] [Main(右)]`
KVM（Corne USB）は **サブモニタの USB ハブ** に接続。サブは PBP で常時両 PC 接続のため、KVM 切替は USB ハブの向き先だけが動きビデオは動かない (メインに挿すと KVM 切替 = ビデオ入力切替になってしまい不可)。

切替スクリプトと watchdog は `/tmp/desktop-switcher.lock` で相互排他。

## 状態定義（4状態、2キーで遷移）

| 状態 | Main(右) | Sub PBP | Sub映像 | 画面の見え方 |
|---|---|---|---|---|
| S1 | Max | On | 左=Air 右=Max | `[Air│Max] [Max]` |
| S3 | Air | On | 左=Max 右=Air | `[Max│Air] [Air]` |
| S7 | Max | Off | Max | `[Max] [Max]` |
| S9 | Air | Off | Air | `[Air] [Air]` |

Key2 (F19) = メイン入替、Key3 (F20) = PBP 切替。

## 運用ルール (必読)

1. **現在メインで使っている Mac 側からスクリプトを実行する**。非メイン側の Corne から F19/F20 を押しても、その PC からは DDC が届かず abort する (BenQ は active input の cable 経由でしか DDC 応答しない)。
2. **次にメインになる PC は awake にしておく**。切替先が sleep だとメインモニタが standby 化して DDC バスごと死に、物理ボタンでしか復旧できなくなる。
3. **BetterDisplay 本体 (GUI) は常に起動**。BD CLI は host app と IPC で通信するため host が落ちていると全操作失敗。起動項目に入れておく。

## 重要な技術情報（ハマりどころ）

- **DDC は active input の cable でしか通らない** — 非メイン PC から main DDC に到達できないのは仕様。スクリプト側は `main_get_input` の空値で検知して abort する。
- **主モニタが standby に入ると DDC バスが完全に死ぬ** — ソフトで復旧不可。物理ボタン / 相手 PC 起床が必要。
- **PBP オフ時の 0x7E 書き込みは BenQ が silent drop する** — exit=0 stderr空 で見かけ成功。不変条件「0x7E=メインPC」は PBP off→on 遷移時に書き直す設計 (`switch-pbp.sh` で実施)。
- **DDC 連続書き込みには sleep 1 が必要**。書き込み後は read-back 検証 (`sub_set_verified` / `main_set_input_verified`) で確実性を担保。
- **PBP 切替直後は DDC が数秒不安定**。`main_get_input` は空値時にリトライ。
- **BetterDisplay `connected=off` にすると DDC 通信も不可**。復旧時は `main_ensure_connected_on` を使う。
- **BetterDisplay の UUID 追跡は落ちることがある** (物理 signal 断など)。`$BD get -identifiers` に含まれない状態。`bd_recover_if_lost` が `perform -reconfigure` (= GUI の「Redetect Displays」) で再取得を試みる。
- **`perform -reconfigure` は諸刃** — 生きている UUID を誤って追跡解除することがあるため、UUID が実際に lost の時だけ呼ぶ (`bd_is_uuid_tracked` で確認してから)。
- **2台の PD2730S は同一モデル名なので UUID で識別**（`-uuid=` 必須、`-name=` 不可）。
- **サブモニタは PBP オン/オフで UUID が変わる**。スクリプトは両 UUID を試行する `sub_get`/`sub_set` を使用。
- **m1ddc の `set pbp` / `set pbp-input` は BenQ では効かない**（Dell 向け実装）。BetterDisplay CLI で任意 VCP コードを叩く。
- **launchd から ~/Documents 配下の bash スクリプトは TCC で実行不可**。watchdog は `~/.local/bin/` にコピーして実行（詳細は m2max-setup.md）。

## 入力値と UUID

| 接続 | 入力値 (0x60) |
|---|---|
| M3 Air → メインモニタ (TB) | 21 |
| M2 Max → メインモニタ (HDMI) | 17 |
| M3 Air → サブモニタ (TB) | 21 |
| M2 Max → サブモニタ (DP) | 15 |

| ディスプレイ | モード | M3 Air UUID | M2 Max UUID |
|---|---|---|---|
| メインモニタ | — | `2DF75969-A2F5-4608-A9B4-429B3A3CA4BB` | `7A782274-C5F3-414C-B90A-41770749B121` |
| サブモニタ | PBP オフ | `B02476A6-81D7-444F-B03B-DC515516025A` | `4A8F5105-1777-4D51-8E49-ECDD133C3D7B` |
| サブモニタ | PBP オン | `4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20` | `C2E62FA2-0938-463E-92B2-FD77960B47C5` |

## 現在のステータス

M3 Air 側セットアップ完了・実機テスト済み。M2 Max 側も `m2max-setup.md` に沿ってセットアップ済み。スクリプトは堅牢化を複数回実施 (`bd_recover_if_lost` / `main_set_input_verified` / non-main PC 検出 / BD host preflight)。残タスクは Vial での Corne キーマップ更新 (F19/F20)、M2 Max 側からの実行テスト、長時間運用テスト。

設計と処理フローの詳細は `switching-design.md` を参照。
