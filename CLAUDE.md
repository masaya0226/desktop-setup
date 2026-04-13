# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

2台の Mac（M2 Max MacBook Pro 14" / M3 MacBook Air）と 2台の BenQ PD2730S モニタを、Corne Cherry キーボードのショートカットキーでモニタ入力を一括切替できる常時稼働デスクトップ環境を構築するプロジェクト。

## ファイル構成

- `switching-design.md` — **最新の設計書**（状態定義、DDC VCPコード、スクリプト仕様、テスト状況、未完了タスク）
- `handoff-context.md` — 初期の議論と決定事項の引き継ぎ資料（iiyama+BenQ時代）
- `desktop-setup-guide.md` — Phase 0〜7 の全セットアップ手順書（iiyama+BenQ時代、参考資料）
- `scripts/m3air/` — M3 Air 用スクリプト（switch-main.sh, switch-pbp.sh, display-watchdog.sh）
- `scripts/m2max/` — M2 Max 用スクリプト（switch-main.sh, switch-pbp.sh, display-watchdog.sh）

## アーキテクチャ

```
[Corne ショートカット] → [Hammerspoon] → [切替スクリプト]
                                              ├ BetterDisplay CLI: メインモニタ DDC制御 (入力切替)
                                              ├ BetterDisplay CLI: サブモニタ DDC制御 (PBP/入力)
                                              ├ BetterDisplay CLI: メインモニタ connected 管理
                                              └ displayplacer: 主ディスプレイ設定
                                                    ↓
                                              [display-watchdog] サブモニタ状態を見てメインモニタ connected 補完
```

物理配置: `[Sub(左,PBP)] [Main(右)]`
KVM（Corne USB）は物理スイッチで切替。

## 状態定義（4状態、2キーで遷移）

| 状態 | Main(右) | Sub PBP | Sub映像 | 画面の見え方 |
|---|---|---|---|---|
| S1 | Max | On | 左=Air 右=Max | `[Air│Max] [Max]` |
| S3 | Air | On | 左=Max 右=Air | `[Max│Air] [Air]` |
| S7 | Max | Off | Max | `[Max] [Max]` |
| S9 | Air | Off | Air | `[Air] [Air]` |

## 重要な技術情報

- **DDC 連続書き込みには sleep 1 が必要**（間隔が短いと無視される）
- **PBP 切替直後は DDC が不安定**（数秒待つ必要あり）
- **PBP 切替で 0x60, 0x7E の値は維持される**（入力設定の再送不要）
- **BetterDisplay connected=off にすると DDC 通信も不可**になる
- **PBP 左右入替**: 0x7E（右/サブ側）を先に変更してから 0x60（左/メイン側）を切替
- m1ddc の `set pbp` / `set pbp-input` は BenQ では効かない（Dell 向け実装）。BetterDisplay CLI で任意 VCP コードを使う
- 2台の PD2730S は同一モデル名のため **UUID で識別**する（`-uuid=` を使用）
- **主ディスプレイ**: 切替後に `displayplacer` でメインモニタ（右）を主ディスプレイに設定

## 現在のステータス

PD2730S x2 構成。UUID・入力値は両 Mac とも確定済み。displayplacer 設定とテストが残タスク。残タスクは `switching-design.md` 末尾を参照。

### 入力値 (確定)

| 接続 | 入力値 |
|---|---|
| M3 Air → メインモニタ (TB) | 21 |
| M2 Max → メインモニタ (HDMI) | 17 |
| M3 Air → サブモニタ (TB) | 21 |
| M2 Max → サブモニタ (DP) | 15 |
