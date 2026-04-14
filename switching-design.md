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

### 状態遷移図

```
     Key2(入替)
S1 ←————————→ S3
↕ Key3(PBP)    ↕ Key3(PBP)
S7 ←————————→ S9
     Key2(入替)
```

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

---

## 運用ルール (重要)

### ルール 1: **現在のメイン PC 側でスクリプトを実行する**

BenQ の DDC バスは「**現在 active な入力**」の cable 経由でしか応答しない。非メイン PC (Corne の KVM を non-main に向けた状態) から `switch-main.sh` / `switch-pbp.sh` を実行しても、メインモニタの DDC を読めず `main_get_input` が空値を返して **abort** する (正しい refusal)。

**やりたい操作の手順**:
1. 今メインで使っている Mac で F19/F20 を押す (Corne KVM が現メインに向いている前提)
2. スクリプト完了後、Corne KVM を物理的に次のメイン PC へ切替

### ルール 2: **次にメインになる PC は必ず awake にしておく**

`switch-main.sh` は main モニタ 0x60 を書き換えて active input を切り替える。切替先 PC が sleep だと、主モニタは新しい input から signal を受けられず **standby** に入る。standby 中は DDC バスごと死ぬため、以後いずれの Mac からも main モニタを触れなくなる (物理ボタン / 相手 PC 起床まで復旧不能)。

### ルール 3: **BetterDisplay 本体 (GUI) は常に起動しておく**

BD の CLI (`$BD get/set`) は **BD GUI 本体 (host app)** と IPC で通信して動く。host app が落ちていると全操作が `Host app might not be running or is not accepting notifications.` で失敗する。`hs.autoLaunch(true)` と同様に BD も起動項目に入れておくこと。

---

## DDC VCP コード一覧（BenQ PD2730S）

| VCP | 用途 | 値 | R | W |
|---|---|---|---|---|
| 0x60 | 入力ソース（メイン / PBP左） | 17=HDMI, 21=TB, 15=DP | ✅ | ✅ |
| 0x7D | PBP モード | 0=オフ, 2=PBPオン | ✅ | ✅ |
| 0x7E | PBPサブ入力（PBP右） | 17=HDMI, 21=TB, 15=DP | ✅ | ✅* |
| 0x7F | 0x7Eの読み取り専用ミラー | 0x7Eと同値 | ✅ | ❌ |

\* **PBP オフ時の 0x7E 書き込みは silent drop される**。

### DDC 操作のハマりどころ

- **DDC は active input の cable でしか通らない** — 非メイン PC から main モニタを触ろうとしても DDC バスに到達しない。主モニタ以外の PC の TB/HDMI 経路は DDC 応答しない (BenQ 仕様)。
- **主モニタが standby に入ると DDC バスごと死ぬ** — 物理ボタン or 相手 PC 起床が復旧条件。ソフトでは戻せない。
- **PBP オフ時、0x7E への書き込みは silent drop される** — `$BD set` は exit=0 stderr空 で見かけ成功を返すが値は変わらない。不変条件「0x7E=メインPC」は PBP オン遷移時に書き直す設計にしてある。
- **連続書き込みには sleep 1 が必要** — 間隔が短いと無視される。`sub_set_verified` が read-back 検証 + リトライでカバー。
- **PBP 切替直後は DDC が数秒間不安定** — `main_get_input` は空値時にリトライする。
- **PBP オン/オフでサブモニタの UUID が変わる** — `sub_get` / `sub_set` は両 UUID を試行する。
- **PBP 切替で 0x60, 0x7E の値は維持される**。
- **2台の PD2730S は同一モデル名**のため UUID で識別する（`-uuid=` 必須）。
- **m1ddc の `set pbp` / `set pbp-input` は BenQ では効かない**（Dell 向け実装）。BetterDisplay CLI で任意 VCP を叩く。
- **KVM は物理スイッチ経由**。DDC 制御不可（全 VCP を KVM 切替前後でダンプし diff ゼロ確認済み）。

---

## BetterDisplay のハマりどころ

### BD の `connected` の意味

`$BD set -uuid=X -connected=off/on` は BD が管理する **論理的な接続状態** (macOS に対して「この display は現在無い」と装うかどうか) を制御する。connected=off だと:

- macOS からは display が消える (Spaces / 壁紙 / wallpaper 位置の再配置が起きる)
- BD CLI の DDC 操作 (`-ddc -vcp=...`) は通らない (`Failed.`)
- GUI 上は display 一覧に「disabled」として表示される (完全消失ではない)

これとは別に、BD が内部で **UUID 追跡そのものを落とす** 状態もある。GUI でその display が一覧に出ない / `get -identifiers` に含まれない状態。この場合は `set -connected=on` も "Failed." になる。原因は物理 EDID が返ってこなくなったとき BD が「もう無い」と判定するため。

### `perform -reconfigure` の諸刃性

BD の Redetect Displays 機能 (`$BD perform -reconfigure`) は GUI の「全て接続する」相当で、UUID lost 状態からの復旧手段になりうる。**が**、reconfigure は **EDID を返さない display を追跡リストから落とす** 動きもある。生きている UUID 相手に reconfigure を呼ぶと逆に UUID を忘れさせてしまうことがあり、状況を悪化させる。

そのため:
- `bd_recover_if_lost(uuid)` — UUID が実際に identifiers から消えている場合**のみ** reconfigure を呼ぶ
- UUID が tracked のままなら何もしない (「生きている UUID を壊さない」)

### BD host (GUI 本体) の生存依存

BD の CLI は host app と IPC で通信する。host app が落ちていると `Host app might not be running or is not accepting notifications.` で全コマンド失敗。スクリプトは起動時に `pgrep -x BetterDisplay` で host alive を確認し、ダメなら abort する。

---

## スクリプト構成と処理フロー

### 3 つのスクリプトの関係

```
                              [Corne F19/F20]
                                    │
                                    ▼
                         ┌─── Hammerspoon ───┐
                         │ (各 Mac で常駐)    │
                         └──────┬────────────┘
                                │
              ┌─────────────────┼───────────────────┐
              ▼                 ▼                   ▼
     F19: switch-main    F20: switch-pbp    (launchd 常駐)
              │                 │            display-watchdog
              │                 │                   │
              └─────┬───────────┘                   │
                    │                               │
                    ▼                               ▼
          /tmp/desktop-switcher.lock ←─── (存在チェックで回避)
                    │
                    ▼
          ┌─────────────────┐
          │  BetterDisplay  │ ← perform -reconfigure (復旧)
          │  CLI + host app │ ← DDC 読み書き
          │                 │ ← connected on/off
          │                 │ ← -main=on (主ディスプレイ)
          └────────┬────────┘
                   │
                   ▼
          ┌──────────────────┐
          │  BenQ PD2730S x2 │
          └──────────────────┘
```

- **切替スクリプト (`switch-main.sh` / `switch-pbp.sh`)** は Hammerspoon から同期起動される。DDC 書き込みと connected 管理を行う一連の atomic な操作。
- **watchdog (`display-watchdog.sh`)** は launchd 常駐で 4 秒毎に走り、**切替スクリプトがカバーしきれない場合** (KVM 切替の前後で非メイン側の connected が残留する等) の補完を担う。
- **ロックファイル** で watchdog と切替スクリプトを排他する (中間状態での誤判定防止)。
- 全ての BD 操作は BD host app が生きていることが前提。

### 共通ヘルパー関数 (4 本のスクリプト間でコピー)

#### 状態確認系

| 関数 | 役割 |
|---|---|
| `bd_host_alive()` | `pgrep -x BetterDisplay` で GUI host app が動いているか確認。preflight で使う。 |
| `bd_is_uuid_tracked(uuid)` | `get -identifiers` の出力を grep して UUID が BD 追跡下にあるか確認。 |
| `bd_recover_if_lost(uuid)` | UUID が tracked なら何もせず成功。lost なら `perform -reconfigure` を呼んで sleep 2 → 再確認。tracked な UUID を壊さないことが鍵。 |

#### メインモニタ DDC

| 関数 | 役割 |
|---|---|
| `main_get_input()` | メインモニタ 0x60 を読む。空値なら 1s 間隔で 5 回リトライ → それでもダメなら `bd_recover_if_lost` → 再度 3 回リトライ。最終的に空なら失敗 (1)。 |
| `main_set_input(v)` | メインモニタ 0x60 に書き込む。stderr "Failed." 検出で 1s 間隔 3 回リトライ → それでもダメなら `bd_recover_if_lost` → 3 回リトライ。 |
| `main_set_input_verified(v)` | `main_set_input` を呼び、sleep 1 → `main_get_input` で read-back → 一致しないなら最大 3 回再挑戦。**非メイン PC からの無効な write を検出して早期 abort するために使う** (switch-main 限定)。 |
| `main_ensure_connected_on()` | `set -connected=on`。"Failed." なら `bd_recover_if_lost` → 1 回リトライ。 |
| `set_main_display()` | `$BD set -main=on` で主ディスプレイをメインモニタに固定。stderr 完全抑制 (効かなくても続行)。 |

#### サブモニタ DDC

| 関数 | 役割 |
|---|---|
| `sub_get(vcp)` | PBP on/off で UUID が変わるので両方試行。最初に空値以外が返ったほうを返す。 |
| `sub_set(vcp, v)` | 両 UUID に順番に書き込み試行。 |
| `sub_set_verified(vcp, v)` | `sub_set` + 1s → read-back → 不一致なら 3 回再挑戦。最後の read-back が空値なら「確認不能」として警告抑制 (PBP 遷移直後の DDC 不安定を黙殺するため)。 |

#### 汎用

| 関数 | 役割 |
|---|---|
| `notify(msg)` | `osascript` で macOS 通知表示。 |

---

### `switch-main.sh` 処理フロー (Key2: メイン入替)

```
[1] ロック取得
    /tmp/desktop-switcher.lock 作成
    trap EXIT で cleanup (sleep 2 → 削除、DDC 物理反映待ち)

[2] preflight
    bd_host_alive → NG なら notify + exit 1

[3] main connected 復旧
    $BD get -connected を見て、"on" 以外なら main_ensure_connected_on を試行
    (失敗しても || true で継続; 後続の main_get_input で最終判定)

[4] 現在状態読み取り
    current_main = main_get_input (リトライ + 必要なら bd_recover)
    current_pbp  = sub_get 0x7D
    current_main が空 → notify "DDC 読み取り失敗" + exit 1
    → これが「非メイン PC から実行された」場合の正しい refusal

[5] トグル方向決定
    current_main == MAIN_AIR なら Air → Max
    current_main == MAIN_MAX なら Max → Air
    TARGET_MAIN / TARGET_SUB_MAIN / TARGET_SUB_OTHER を確定

[6] メインモニタ 0x60 書き込み (verified)
    main_set_input_verified TARGET_MAIN
    書き込み → read-back → 不一致ならリトライ
    最終的に一致しなければ notify + exit 1
    → 非メイン側の silent fail / 書き込み未反映を検出

[7] サブモニタ入力切替
    PBP on の場合:
      sleep 1
      sub_set_verified 0x7E = TARGET_SUB_MAIN  (新メインPCをサブ右へ)
      sub_set_verified 0x60 = TARGET_SUB_OTHER (新他PCをサブ左へ)
    PBP off の場合:
      sleep 1
      sub_set_verified 0x60 = TARGET_SUB_MAIN  (0x60 のみ; 0x7E は silent drop するため触らない)

[8] 自分の connected 管理 (幽霊スペース対策)
    MY_MAIN_INPUT == TARGET_MAIN (自分が新メイン) の場合:
      main_ensure_connected_on
      sleep 1
      set_main_display
    else (自分が非メインになる) の場合:
      $BD set -connected=off

[9] 通知
    notify "M3 Air に切替" / "M2 Max に切替"

[10] trap cleanup
    sleep 2 → ロック削除
```

### `switch-pbp.sh` 処理フロー (Key3: PBP 切替)

```
[1] ロック取得 (switch-main と同じ)

[2] preflight (同上)

[3] main connected 復旧 (同上)

[4] メインPC 判定
    current_main = main_get_input
    空なら notify + exit 1
    is_self_main = (current_main == MY_MAIN_INPUT)
    SUB_MAIN_PC / SUB_OTHER_PC を current_main から決定 (空値時の Max 決め打ちはしない)

[5] 現在の PBP 状態
    current_pbp = sub_get 0x7D

[6] PBP トグル
    PBP on → off の場合:
      sub_set_verified 0x60 = SUB_MAIN_PC  (先に [main|main] にしてから PBP off で他PCの瞬間露出を防ぐ)
      sub_set_verified 0x7D = 0
    PBP off → on の場合:
      sub_set_verified 0x7D = 2
      sub_set_verified 0x7E = SUB_MAIN_PC  (0x7E は switch-main の PBP off 分岐で書けないのでここで書き直す)
      sub_set_verified 0x60 = SUB_OTHER_PC

[7] 自分の connected 管理
    is_self_main == 1 の場合:
      main_ensure_connected_on
      sleep 1
      set_main_display
    else:
      $BD set -connected=off
    (PBP トグルはメイン PC を変えないので idempotent に固定するだけ)

[8] 通知
    notify "PBP オン" / "PBP オフ"

[9] trap cleanup (sleep 2 → ロック削除)
```

### `display-watchdog.sh` 処理フロー (launchd 常駐)

```
無限ループ:
  [1] ロックチェック
      /tmp/desktop-switcher.lock が存在するなら sleep 2 して continue
      30 秒以上古いなら強制削除 (trap 漏れ保険)

  [2] サブモニタ状態取得
      pbp      = sub_get 0x7D
      sub_main = sub_get 0x60
      どちらか空なら sleep 4 して continue

  [3] main connected の期待値判定
      PBPオン:
        sub_main == 自分 → サブ左=自分、メインは他PC → off
        sub_main ≠ 自分 → 自分がメイン → on
      PBPオフ:
        sub_main == 自分 → 自分が active PC → on
        sub_main ≠ 自分 → 他PC が active → off

  [4] current_connected と不一致なら set
      $BD set -connected=<should_be>

  [5] sleep 4
```

### 相互排他と責任分担

| 問題 | 担当 |
|---|---|
| 入力切替 + 主ディスプレイ固定 | `switch-main.sh` |
| PBP on/off トグル + PBP on 時の 0x7E 書き直し | `switch-pbp.sh` |
| KVM 切替後の非メイン PC の connected 残留補完 | `display-watchdog.sh` |
| 切替スクリプトと watchdog のレース防止 | `/tmp/desktop-switcher.lock` (mutex) |
| BD UUID lost 状態からの復旧 | `bd_recover_if_lost` (必要時のみ `perform -reconfigure`) |

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

## 既知の失敗モードと対処

### 症状 1: 切替キーを押しても何も起きない (exit 1 abort)

**原因**: 非メイン PC 側で実行した。`main_get_input` が DDC 応答を取れず空値 → `notify "メインモニタ DDC 読み取り失敗"` → abort。

**対処**: Corne KVM を現メイン PC 側に切替えてから押し直す。

### 症状 2: メインモニタが真っ暗なまま戻らない (standby)

**原因**: 切替後のメイン PC (新 active input 側) が sleep / 画面出力無効 で、主モニタが新 input で signal を受けられずに standby 化した。

**対処**: 物理。以下のいずれかで復旧:
1. 対象 Mac を起こす (key / lid open / WOL)
2. 主モニタの物理 input ボタンで手動で別 input へ
3. 主モニタ電源長押しでリセット

standby 中は DDC バスが死ぬため **ソフトウェアでは復旧できない**。

### 症状 3: 片方の PC だけ見えない / BD GUI で display 一覧から消えた

**原因**: BD の UUID 追跡が落ちた (物理的な signal 断 or reconfigure の副作用)。

**対処**: スクリプトの `bd_recover_if_lost` が自動で試みるが、物理 signal が戻っていない限り再取得できない。物理確認 → `$BD perform -reconfigure` を手動実行も OK。

### 症状 4: BD CLI が "Host app might not be running" を返す

**原因**: BetterDisplay GUI 本体が落ちている (OOM / 手動終了 / アップデート)。

**対処**: `open -n -a BetterDisplay` で再起動。`hs.autoLaunch(true)` 相当で BD も起動項目に入れておくと予防できる。

---

## 過去の修正履歴（抜粋）

主要な設計変更は git log 参照。特に重要な変更:

- **0x7E silent drop 対策** (commit 2e42f0a) — PBP オフ時の 0x7E 書き込みは BenQ が黙殺するため、PBP オン遷移時に書き直す方式に変更。`sub_set_verified` を導入。
- **ロックファイル排他** (commit 0856ae4) — watchdog が切替スクリプトの中間状態を読まないよう `/tmp/desktop-switcher.lock` で mutex。
- **watchdog PBP off 対応** (commit 3318005) — 旧 watchdog は PBP off 時「触らない」で非メイン側の connected 残留が残る問題があった。両モードで sub 0x60 で判定するよう修正。
- **スクリプト堅牢化** (commit 6a7b08f) — `bd_recover` / `main_*_verified` / `bd_host_alive` / preflight を導入。非メイン PC からの誤 write を検出して abort する設計に。
- **bd_recover の誤用修正** (commit 917cf5d) — reconfigure が生きている UUID を誤って壊す事故を防ぐため、`bd_recover_if_lost` で UUID lost 時のみ呼ぶように変更。

---

## テスト状況

- [x] S1↔S3 / S7↔S9 (switch-main.sh、PBPオン/オフ時のメイン入替)
- [x] S1↔S7 / S3↔S9 (switch-pbp.sh、PBP on/off 切替)
- [x] switch-main.sh の主ディスプレイ維持 (BetterDisplay `-main=on`)
- [x] 0x7E silent drop 対策後の全 4 状態遷移
- [x] watchdog ロック排他動作
- [x] 非メイン PC 実行時の正常な abort (exit 1 + 通知)
- [ ] M2 Max 側からの実行テスト (堅牢化後)
- [ ] 長時間運用テスト

## 残タスク

- [ ] Vial で Corne の Adjust レイヤーに F19/F20 配置 (手動作業)
- [ ] M2 Max 側からの動作テスト (堅牢化後)
- [ ] 長時間運用テスト
- [ ] BetterDisplay を macOS 起動項目に入れる (BD host 前提のため)
- [ ] PBP 右側(0x7E) の KVM 連動可否調査 (OSD設定 / DDC PBP swap、余裕あれば)
