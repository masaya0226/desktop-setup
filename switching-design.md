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

BenQ PD2730S x2 + Mac x2（M2 Max / M3 Air）。物理配置: `[サブモニタ(左)] [メインモニタ(右)]`。

### KVM (Corne) の接続先: サブモニタ側

Corne キーボードは **サブモニタの USB ハブ** に接続している。これは意図的な設計で:

- サブモニタは PBP で **両 PC を同時に接続** しているため、BenQ 内蔵 KVM は「現在 PBP で映っている側の PC」に USB ハブを渡すだけで済む。KVM 切替は USB の付け替えだけで完結し、ビデオ入力は一切動かない。
- もし Corne をメインモニタ側に挿していると、メインモニタは PBP を使っていない (常に 1 つの PC のみ表示) ため、KVM で相手 PC に切替えようとすると **ビデオ入力そのものも切替える** 必要がある。KVM 切替がそのまま入力切替になってしまい、Corne で操作したい「USB だけ渡す」動作ができない。

なので Corne は **必ず PBP 有効なサブモニタ側** の USB に挿す。

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

### ルール 1: **どちらの Mac からでもスクリプトは実行できる**

BenQ PD2730S の DDC バスは、BetterDisplay が UUID を tracked かつ自側の `connected=on` の状態なら、**active input に関係なく read/write 両方効く**。非メイン PC 側から F19/F20 を押しても問題なく切替が動作する (実測済)。

スクリプトは preflight で自側の `connected=off` を一時的に `on` に復旧してから DDC を叩く。

### ルール 2: **次にメインになる PC は必ず awake にしておく**

`switch-main.sh` は main モニタ 0x60 を書き換えて active input を切り替える。切替先 PC が sleep で HDMI/TB の出力をしていない場合、主モニタは新しい input から signal を受けられず **信号なし状態** になる。

信号なし自体は BD の DDC アクセスを完全には止めないが、ユーザ視点では「真っ暗な main モニタ」になり復旧が面倒になる。`main_set_input_verified` の read-back は通るケースが多いので検知には限界がある → 事前に切替先を起こしておくのが rule。

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

- **DDC は自側の cable 経由で active input によらず通る** — 「非メイン側からは DDC 届かない」という直感は間違い。BD が UUID を tracked かつ `connected=on` なら read/write 両方効く (実測確認済)。失敗の真因は BD 内部の UUID lost 状態や host app 停止、`connected=off` などであり、cable の選択とは無関係。
- **主モニタが信号なし状態でも DDC は生きている可能性が高い** — 過去に「DDC が死ぬ」と思われた事例は実際には BD 内部の UUID tracking 落ちだった。ただし monitor 電源 off / 物理 cable 断は別 (未検証)。
- **PBP オフ時、0x7E への書き込みは silent drop される** — `$BD set` は exit=0 stderr空 で見かけ成功を返すが値は変わらない。不変条件「0x7E=メインPC」は PBP オン遷移時に書き直す設計にしてある。
- **連続書き込みには sleep 1 が必要** — 間隔が短いと無視される。`sub_set_verified` が read-back 検証 + リトライでカバー。
- **PBP 切替直後は DDC が数秒間不安定** — `main_get_input` は空値時にリトライする。
- **BD の UUID は不変ではない** — TB/DP の再列挙で `portID` が変わると、BD は同一個体に別 UUID を採番する (2026-08 に実際に発生)。UUID をスクリプトにハードコードしてはいけない。詳細は下の「UUID 動的解決」を参照。
  - なお旧版にあった「PBP オン/オフでサブモニタの UUID が変わる」は**誤診**だった。BD の記録上サブモニタ個体 (serial `E1T00045019`) の UUID は 1 つしかなく、PBP をまたいでも変わらない。当時「サブ PBP オフ」として記録していた UUID は実際にはメインモニタのものだった。
- **PBP 切替で 0x60, 0x7E の値は維持される**。
- **2台の PD2730S は同一モデル名**のため `-name=` では識別できない。スクリプトは EDID の `alphanumericSerial` から UUID を毎回引き直し、`-uuid=` に渡す。
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

### `perform -reconfigure` の諸刃性と自動呼び出し無効化 (2026-04)

BD の Redetect Displays 機能 (`$BD perform -reconfigure`) は GUI の「全て接続する」相当で、UUID lost 状態からの復旧手段になりうる。**が**、以下の 2 つの問題が判明している:

1. **生きている UUID を壊す** — reconfigure は EDID を返さない display を追跡リストから落とす。生きている UUID 相手に呼ぶと逆に UUID を忘れさせてしまい状況を悪化させる。
2. **BD host を不安定化させる** — watchdog の in-flight CLI と並列 DDC 書き込みが重なった状態で reconfigure が走ると、BD host (GUI 本体) が unresponsive になり以降の全 CLI が hang する事象を観測 (DDC 並列化導入後)。

そのため現在の実装では **reconfigure を一切呼ばない**。代わりに下記の UUID 動的解決で復旧する。

### UUID 動的解決 (2026-08)

**BD の UUID は不変ではない。** 2026-08 に、メインモニタが TB の再列挙で `portID` 209768448 → 209768464 に変わり、BD が同一個体 (serial `GAS00262019`、EDID 完全一致、`ioDisplayLocation` も同一) に**別 UUID を採番**した。ハードコードしていた UUID は `Failed.` を返すようになり、切替が完全に停止した。

さらに悪いことに、新しく採番された UUID がスクリプトの `SUB_UUID_OFF` 定数と同じ値だったため、サブモニタ向けの DDC 書き込みがメインモニタに飛ぶ状態になっていた。

そこで UUID のハードコードを廃止し、**個体固有の EDID シリアルから毎回引き直す**方式に変更した。

| キー | メインモニタ (右) | サブモニタ (左, PBP) |
|---|---|---|
| `alphanumericSerial` (第一キー) | `GAS00262019` | `E1T00045019` |
| `model` (第二キー) | `32908` | `32907` |

- シリアルは EDID 由来なので **portID / PBP 状態 / 接続先 Mac に依存しない**。M3 Air 側と M2 Max 側で同じ定数が使える。
- EDID が読めず BD が Generic Display 扱いにするケースがあるため、`model` を第二キーにフォールバックする。
- `resolve_display_uuids()` が両方を引き、**両方取れて別物である**ことを確認して初めて成功を返す (片方しか取れない / 同じ UUID に解決された場合は abort)。
- 旧 `bd_recover_if_lost` が担っていた「読めなくなったときの復旧」は、`resolve_display_uuids()` の呼び直しが担う。reconfigure と違い BD host に副作用がなく、まさに起きた障害 (UUID の変更) をピンポイントで直せる。
- 診断は `bash scripts/resolve-displays.sh` で行う。追跡中のディスプレイ一覧・解決結果・DDC 実測値をまとめて表示する。

### 幽霊スペースエントリ (2026-08)

**UUID 世代交代と `connected` トグルが噛み合うと、macOS 側に消せない残骸が残る。**

2026-08-27 に Mission Control が起動せず、フルスクリーンのスペースにも切り替えられなくなった。原因は `com.apple.spaces` の Monitors に、実在しないディスプレイのエントリが残っていたこと。

```
Monitor: Main          Current Space id=3   Spaces 4 件
Monitor: 4B3EC4EE-…    Current Space id=6   Spaces 2 件
Monitor: 21CAEADE-…    Current Space なし   Spaces 0 件  ← 幽霊
```

Mission Control は全ディスプレイの current space を列挙してから合成アニメーションを組むため、**current space が nil のエントリが混ざると起動できない**。

#### 生まれる経路

1. `connected=off` の状態 (自分は非メイン、サブ左に表示されている)
2. その最中に BD が portID 変化で UUID を再採番する
3. watchdog が**新** UUID で `connected=on` を打つ
4. macOS からは「旧 UUID の display が消えたまま、新 UUID の display が現れた」ように見える
5. 旧 UUID のエントリが Current Space を持たない残骸として永久に残る

**`connected` の状態を UUID の世代交代をまたいで持ち越すと幽霊になる**、というのが本質。

#### なぜ今まで起きなかったか

UUID ハードコード時代は、世代交代が起きると BD への書き込みが全て `Failed.` になり、**結果として connected を触らなくなっていた**。切替機能そのものが死ぬ代わりに、幽霊も生まれなかった。UUID 動的解決 (2026-08) で追従できるようになった副作用として顕在化したもので、動的解決が誤りなのではなく、止まっていた経路が復活しただけ。

#### 対策 (2026-08-27)

| 層 | 対策 | 実装 |
|---|---|---|
| 予防 | 世代交代を検知したら `connected` を 12 秒触らない | `resolve_and_track()` + `settle_left` |
| 検出 | 4 分毎に幽霊エントリの有無を確認し、あれば通知 | `count_ghost_spaces()` |
| 診断 | 人間が構成を目視確認する | `bash scripts/check-spaces-health.sh` |

予防は「portID がバタついている最中に何度も付け外しして残骸を量産する」のを防ぐもので、世代交代そのものは止められない。1 件も作らせない保証はないため、検出とセットで運用する。

#### 掃除の方法

**幽霊エントリは `killall Dock` でも plist 編集でも消えない。** WindowServer がメモリ上に構成を保持しており、`com.apple.spaces.plist` はその写しにすぎないため。

| 方法 | 効果 |
|---|---|
| `killall Dock` | 応急処置。Dock がメモリ上の構成を組み直すので Mission Control は一時的に復活する。**幽霊自体は残るので再発する** |
| plist から該当エントリを削除 | 効かない。WindowServer が次に書き込む際に元に戻る |
| **ログアウト → 再ログイン** | **恒久的な解消。** WindowServer のユーザセッションごと作り直されるので、実在しないディスプレイのエントリは落ちる |

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
          │  BetterDisplay  │ ← get -identifiers (UUID 動的解決)
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
| `bd_uuid_by_field(field, want)` | `get -identifiers` を 1 行ずつ読み、指定フィールドが `want` に一致するエントリの UUID を返す。 |
| `resolve_display_uuids()` | `MAIN_UUID` / `SUB_UUID` を serial (→ model フォールバック) から引き直す。両方取れて別物なら成功。preflight と、DDC が読めなくなった時の復旧に使う。 |

#### メインモニタ DDC

| 関数 | 役割 |
|---|---|
| `main_get_input()` | メインモニタ 0x60 を読む。空値なら 1s 間隔で 5 回リトライ → それでもダメなら `resolve_display_uuids` で引き直して 3 回再挑戦 → 失敗 (1)。 |
| `main_set_input(v)` | メインモニタ 0x60 に書き込む。stderr "Failed." 検出で 1s 間隔 3 回リトライ → それでもダメなら `resolve_display_uuids` で引き直して 3 回再挑戦 → 失敗。 |
| `main_set_input_verified(v)` | `main_set_input` を呼び、sleep 1 → `main_get_input` で read-back → 一致しないなら最大 3 回再挑戦。**非メイン PC からの無効な write を検出して早期 abort するために使う** (switch-main 限定)。 |
| `main_ensure_connected_on()` | `set -connected=on`。"Failed." なら `resolve_display_uuids` で引き直して 1 回リトライ。 |
| `set_main_display()` | `$BD set -main=on` で主ディスプレイをメインモニタに固定。stderr 完全抑制 (効かなくても続行)。 |

#### サブモニタ DDC

| 関数 | 役割 |
|---|---|
| `sub_get(vcp)` | `SUB_UUID` から VCP を読む。書き込み直後は DDC が不安定で空読みするため 1s 間隔で 3 回リトライ。 |
| `sub_set(vcp, v)` | `SUB_UUID` に書き込む。 |
| `sub_set_verified(vcp, v)` | `sub_set` + 1s → read-back → 不一致なら 3 回再挑戦。空読み時は `resolve_display_uuids` で引き直してから再挑戦する。最後の read-back が空値なら「確認不能」として警告抑制 (PBP 遷移直後の DDC 不安定を黙殺するため)。 |

#### watchdog 専用 (幽霊スペース対策、2026-08-27 追加)

| 関数 | 役割 |
|---|---|
| `resolve_and_track()` | `resolve_display_uuids()` を呼び、UUID が前回と変わっていたら世代交代として記録・通知し `settle_left` をセットする。**watchdog では生の `resolve_display_uuids()` ではなく必ずこちらを使う。** 解決に失敗した場合は `PREV_*` を上書きしない (単なる読み取り失敗を世代交代と誤認せず、次に引けた時に正しく比較するため)。 |
| `count_ghost_spaces()` | `com.apple.spaces` の Monitors から「`Display Identifier` はあるが `Current Space` がない」エントリ数を返す。`defaults` + `grep -c` だけで判定するので python 等を起動せずに済む。それでも 4 秒ループから毎回叩くには重いので `GHOST_CHECK_EVERY` で間引いて呼ぶ。 |
| `load_prev_uuids()` / `save_prev_uuids()` | 前回解決した UUID を `/tmp/desktop-watchdog.state` に永続化。`/tmp` に置くのは意図的で、再起動時は macOS 側の Spaces も作り直されるため比較対象が無いのが正しい。 |

#### 汎用

| 関数 | 役割 |
|---|---|
| `notify(msg)` | `osascript` で macOS 通知表示。 |
| `log(msg)` | タイムスタンプ付きで stdout に出力 (watchdog のみ)。launchd の `StandardOutPath` = `/tmp/desktop-watchdog.out.log` に落ちる。平常時は無言で、状態が変わった時だけ書く。 |

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

[4] 現在状態読み取り (並列実行)
    current_main = main_get_input  ┐ 別 DDC バスなので
    current_pbp  = sub_get 0x7D    ┘ メイン/サブを並列発射し wait で回収
    current_main が空 → notify "DDC 読み取り失敗" + exit 1
    → BD UUID lost / host app 停止 / 物理断など本当に読めない時の safeguard

[5] トグル方向決定
    current_main == MAIN_AIR なら Air → Max
    current_main == MAIN_MAX なら Max → Air
    TARGET_MAIN / TARGET_SUB_MAIN / TARGET_SUB_OTHER を確定

[6] メイン + サブ DDC 書き込み (並列実行)
    別 DDC バスなのでメイン/サブを並列発射。内部は以下:
    - メイン: main_set_input_verified TARGET_MAIN (書き + read-back; 失敗なら exit 1)
    - サブ PBP on: sub_set_verified 0x7E=TARGET_SUB_MAIN → 0x60=TARGET_SUB_OTHER (同一バスなので順序維持)
    - サブ PBP off: sub_set_verified 0x60=TARGET_SUB_MAIN (0x7E は silent drop するため触らない)
    sub 側ヘルパーは UUID の引き直ししか行わず BD host に副作用がないため並走時の競合なし。

[8] 自分の connected 管理 (幽霊スペース対策)
    MY_MAIN_INPUT == TARGET_MAIN (自分が新メイン; switch-main は現メイン側
    からしか実行できない構造上ここには通常こない。防御コード):
      main_ensure_connected_on
      sleep 1
      set_main_display
    else (自分が新非メインになる):
      PBP on の場合のみ:
        $BD set -connected=off   # 自分はサブ左に映るので幽霊スペース防止
      PBP off の場合:
        何もしない (自分はどこにも映らないので connected 状態は無関係)

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

[4] メインPC 判定 + PBP 状態取得 (並列実行)
    current_main = main_get_input  ┐ 別 DDC バスなので並列
    current_pbp  = sub_get 0x7D    ┘
    current_main が空なら notify + exit 1
    is_self_main = (current_main == MY_MAIN_INPUT)
    SUB_MAIN_PC / SUB_OTHER_PC を current_main から決定 (空値時の Max 決め打ちはしない)

[5] PBP トグル
    PBP on → off の場合:
      sub_set_verified 0x60 = SUB_MAIN_PC  (先に [main|main] にしてから PBP off で他PCの瞬間露出を防ぐ)
      sub_set_verified 0x7D = 0
    PBP off → on の場合:
      sub_set_verified 0x7D = 2
      sub_set_verified 0x7E = SUB_MAIN_PC  (0x7E は switch-main の PBP off 分岐で書けないのでここで書き直す)
      sub_set_verified 0x60 = SUB_OTHER_PC

[6] 自分の connected 管理
    new_pbp = (current_pbp == 2 ? 0 : 2)
    is_self_main == 1 の場合:
      main_ensure_connected_on
      sleep 1
      set_main_display
    else (自分が非メイン):
      new_pbp == 2 の場合のみ:
        $BD set -connected=off   # 自分はサブ左に映るので幽霊スペース防止
      new_pbp == 0 の場合:
        何もしない (自分はどこにも映らない)

[7] 通知
    notify "PBP オン" / "PBP オフ"

[8] trap cleanup (sleep 2 → ロック削除)
```

### `display-watchdog.sh` 処理フロー (launchd 常駐)

```
起動時:
  load_prev_uuids   (/tmp/desktop-watchdog.state から前回の UUID を読む)
  resolve_and_track

無限ループ:
  [1] ロックチェック
      /tmp/desktop-switcher.lock が存在するなら sleep 2 して continue
      30 秒以上古いなら強制削除 (trap 漏れ保険)

  [2] 幽霊スペースの定期チェック (GHOST_CHECK_EVERY=60 周期 = 4 分毎)
      count_ghost_spaces > 0 なら log + notify (GHOST_RENOTIFY_SEC=1h に 1 回まで)
      connected 制御とは独立した健全性監視なので、DDC が読めていようがいまいが回す

  [3] UUID 未解決なら resolve_and_track で引き直し
      世代交代を検知したら settle_left = SETTLE_CYCLES(3) をセット

  [4] サブモニタ状態取得
      pbp      = sub_get 0x7D
      sub_main = sub_get 0x60
      どちらか空なら resolve_and_track して sleep 4 → continue

  [5] main connected の期待値判定
      PBPオン:
        sub_main == 自分 → サブ左=自分、メインは他PC → off
        sub_main ≠ 自分 → 自分がメイン → on
      PBPオフ:
        sub_main == 自分 → 自分が active PC → on
        sub_main ≠ 自分 → 自分は不可視 → should_be 未設定 (何もしない)

  [6] should_be が決まっていて、current_connected と不一致なら set
      ただし settle_left > 0 の間は書き込みを見送り log に残すだけ
      → UUID がバタついている最中の付け外しが幽霊エントリを量産するため。
        数周期 (最大 12 秒) 遅れて反映されても実害はない

  [7] settle_left をデクリメント

  [8] sleep 4
```

**設計意図**: watchdog が必要なのは「他 PC 側からの switch 実行で、自分が新メインに
なる遷移のあと、自分の connected=off 残留を on に戻す」ケースのみ。
PBP off で自分が非メインかつ不可視の状態では、connected の論理値は
ユーザ体験に影響しないので触らない (Spaces 再配置コスト回避)。

### 相互排他と責任分担

| 問題 | 担当 |
|---|---|
| 入力切替 + 主ディスプレイ固定 | `switch-main.sh` |
| PBP on/off トグル + PBP on 時の 0x7E 書き直し | `switch-pbp.sh` |
| KVM 切替後の非メイン PC の connected 残留補完 | `display-watchdog.sh` |
| 切替スクリプトと watchdog のレース防止 | `/tmp/desktop-switcher.lock` (mutex) |
| BD の UUID 変更 / lost への追随 | `resolve_display_uuids()` が serial (→ model) から引き直す。preflight と DDC 失敗時の両方で呼ぶ。 |
| UUID 世代交代の検知と、直後の connected 書き込み抑制 | `resolve_and_track()` + `settle_left` (watchdog、12 秒) |
| 幽霊スペースエントリの検出と通知 | `count_ghost_spaces()` (watchdog、4 分毎) |
| 幽霊スペースの人力診断 | `bash scripts/check-spaces-health.sh` |

---

## 接続構成

| 接続 | ケーブル | 入力値 (0x60) |
|---|---|---|
| M3 Air → メインモニタ | Thunderbolt | 21 (TB) |
| M2 Max → メインモニタ | HDMI | 17 (HDMI) |
| M3 Air → サブモニタ | Thunderbolt | 21 (TB) |
| M2 Max → サブモニタ | DisplayPort | 15 (DP) |

## ディスプレイ識別子

**UUID はハードコードしない** (2026-08 に BD が同一個体へ別 UUID を採番して切替が全停止したため)。スクリプトは以下のシリアル / モデル番号から `get -identifiers` を引いて UUID を実行時に解決する。EDID 由来なので両 Mac で共通の値が使える。

| ディスプレイ | `alphanumericSerial` | `model` |
|---|---|---|
| メインモニタ (右) | `GAS00262019` | `32908` |
| サブモニタ (左, PBP) | `E1T00045019` | `32907` |

現在の解決結果と DDC 実測値は `bash scripts/resolve-displays.sh` で確認する。

<details>
<summary>参考: かつてハードコードしていた UUID (現在は使用しない)</summary>

| ディスプレイ | M3 Air UUID | M2 Max UUID |
|---|---|---|
| メインモニタ | `2DF75969-…` → 2026-08 に `B02476A6-…` へ変更 | `7A782274-…` |
| サブモニタ | `4B3EC4EE-…` | `C2E62FA2-…` |

旧表にあった「サブモニタ PBP オフ」の UUID (`B02476A6-…` / `4A8F5105-…`) は誤記で、実体はメインモニタだった。当時メインの UUID とは別値だったため `sub_get` のフォールバックが働き、偶然正しく動いていた。

</details>

---

## 既知の失敗モードと対処

### 症状 1: 切替キーを押しても何も起きない (exit 1 abort)

**原因**: `main_get_input` が DDC 応答を取れず空値。主な原因は:
- BetterDisplay 本体 (host app) が動いていない
- BD が main UUID を tracking から落としている (`get -identifiers` に main が無い)
- 物理 cable 断

**対処**:
- BD host を起動 (`open -a BetterDisplay`)
- UUID lost はスクリプトが自動復旧せず abort するので、BD host を再起動 (`pkill -9 BetterDisplay && open -a BetterDisplay`)
- それでもダメなら物理 cable 再接続

### 症状 2: メインモニタが真っ暗なまま戻らない (信号なし)

**原因**: 切替後のメイン PC (新 active input 側) が sleep / 画面出力無効 で、主モニタが新 input で signal を受けられない。

**対処**: 物理対応。
1. 対象 Mac を起こす (key / lid open / WOL)
2. 主モニタの物理 input ボタンで手動で別 input へ
3. 主モニタ電源長押しでリセット

DDC バス自体は生きていることが多いが、ユーザ視点では main モニタが真っ暗なので実害は大きい。事前に切替先を awake にしておくのが予防策。

### 症状 3: 片方の PC だけ見えない / BD GUI で display 一覧から消えた

**原因**: BD の UUID 追跡が落ちた (物理的な signal 断) か、UUID が別値に採番し直された。

**対処**: まず `bash scripts/resolve-displays.sh` を実行し、メイン / サブが両方解決できているか確認する。解決できていれば UUID 変更は自動追随済みなので問題ない。解決できていない (= BD が個体を見失っている) 場合は物理 signal を戻す (cable / 入力ボタン / 切替先 PC を awake にする)。BD host 再起動 (`pkill -9 BetterDisplay && open -a BetterDisplay`) も有効。`$BD perform -reconfigure` は生きている UUID を壊すリスクがあるので最終手段。

### 症状 4: BD CLI が "Host app might not be running" を返す

**原因**: BetterDisplay GUI 本体が落ちている (OOM / 手動終了 / アップデート)。

**対処**: `open -n -a BetterDisplay` で再起動。`hs.autoLaunch(true)` 相当で BD も起動項目に入れておくと予防できる。

### 症状 5: Mission Control が開かない / フルスクリーンのスペースに切り替えられない

**原因**: `com.apple.spaces` に幽霊ディスプレイのエントリ (Current Space を持たない Monitor) が残っている。UUID 世代交代を `connected=off` のままでまたいだときに生まれる。詳細は「幽霊スペースエントリ (2026-08)」の節。

**対処**: まず `bash scripts/check-spaces-health.sh` を実行する。幽霊の有無に加えて、Mission Control 系ホットキーの enabled 状態も表示するので、ショートカット設定側の問題と切り分けられる。

幽霊があれば **ログアウト → 再ログイン** で解消する。今すぐ Mission Control を使いたい場合の応急処置は `killall Dock` (メモリ上の構成が組み直されて一時的に復活するが、幽霊は残るので再発する)。

なお幽霊があること自体は「即座に壊れている」ことを意味しない。Dock 再起動直後は動く。残骸が残ったまま次の Spaces 再配置が起きると壊れる、という関係。

---

## 過去の修正履歴（抜粋）

主要な設計変更は git log 参照。特に重要な変更:

- **0x7E silent drop 対策** (commit 2e42f0a) — PBP オフ時の 0x7E 書き込みは BenQ が黙殺するため、PBP オン遷移時に書き直す方式に変更。`sub_set_verified` を導入。
- **ロックファイル排他** (commit 0856ae4) — watchdog が切替スクリプトの中間状態を読まないよう `/tmp/desktop-switcher.lock` で mutex。
- **watchdog PBP off 対応** (commit 3318005) — 旧 watchdog は PBP off 時「触らない」で非メイン側の connected 残留が残る問題があった。両モードで sub 0x60 で判定するよう修正。
- **スクリプト堅牢化** (commit 6a7b08f) — `bd_recover` / `main_*_verified` / `bd_host_alive` / preflight を導入。非メイン PC からの誤 write を検出して abort する設計に。
- **bd_recover の誤用修正** (commit 917cf5d) — reconfigure が生きている UUID を誤って壊す事故を防ぐため、`bd_recover_if_lost` で UUID lost 時のみ呼ぶように変更。
- **UUID 動的解決への移行** (2026-08) — メインモニタが TB の再列挙で portID が変わり、BD が同一個体 (serial `GAS00262019`) に別 UUID `B02476A6-…` を採番。ハードコードしていた `MAIN_UUID` が `Failed.` を返すようになり切替が全停止した。さらに新 UUID が `SUB_UUID_OFF` 定数と同値だったため、サブ向け DDC 書き込みがメインモニタに飛ぶ危険もあった。UUID のハードコードを廃止し、EDID シリアル (→ model フォールバック) から毎回引き直す方式へ変更。あわせて診断用 `scripts/resolve-displays.sh` を追加し、単一 UUID 化で失われた `sub_get` のリトライを明示的に復活。
- **幽霊スペースエントリ対策** (2026-08-27) — Mission Control が起動せず、フルスクリーンのスペースにも切り替えられなくなった。`com.apple.spaces` に実在しないディスプレイのエントリ (`21CAEADE-…`、Current Space なし) が残っていたのが原因。`connected=off` のまま UUID 世代交代をまたぐと旧 UUID のエントリが残骸化する経路を特定した。UUID ハードコード時代は世代交代で書き込みが全て `Failed.` になり結果的に connected を触らなくなっていたため発現せず、動的解決への移行で経路が復活したもの。watchdog に世代交代検知 (`resolve_and_track`)・安定化待ち (`settle_left`)・幽霊の定期検出 (`count_ghost_spaces`) を追加し、診断用 `scripts/check-spaces-health.sh` を新設。掃除は再ログインが必要 (WindowServer がメモリ上に構成を持つため `killall Dock` や plist 編集では消えない)。
- **DDC 並列化 + 自動 reconfigure 無効化** (2026-04) — メイン/サブは別 DDC バスなので、読み書きをメイン vs サブで並列発射。書き込みベンチで 9.4s → 5.4s (約43%短縮)。同時に、watchdog の in-flight CLI と並列書き込みが reconfigure と衝突し BD host を unresponsive にする事象を観測したため、`bd_recover_if_lost` の自動 reconfigure を無効化し UUID lost は abort する方針に変更。

---

## テスト状況

- [x] S1↔S3 / S7↔S9 (switch-main.sh、PBPオン/オフ時のメイン入替)
- [x] S1↔S7 / S3↔S9 (switch-pbp.sh、PBP on/off 切替)
- [x] switch-main.sh の主ディスプレイ維持 (BetterDisplay `-main=on`)
- [x] 0x7E silent drop 対策後の全 4 状態遷移
- [x] watchdog ロック排他動作
- [x] 非メイン PC 実行時の正常な abort (exit 1 + 通知)
- [x] 幽霊スペース検出 (`count_ghost_spaces` が実データで残骸 1 件を検出、`check-spaces-health.sh` の表示も確認)
- [ ] UUID 世代交代の検知と settle 動作 (実際の再採番が起きるまで検証不可。state ファイルへの記録までは確認済み)
- [ ] M2 Max 側からの実行テスト (堅牢化後)
- [ ] 長時間運用テスト

## 残タスク

- [ ] Vial で Corne の Adjust レイヤーに F19/F20 配置 (手動作業)
- [ ] M2 Max 側からの動作テスト (堅牢化後)
- [ ] 長時間運用テスト
- [ ] BetterDisplay を macOS 起動項目に入れる (BD host 前提のため)
- [ ] **幽霊エントリ `21CAEADE-…` の解消** — ログアウト → 再ログインが必要。次に PC を落とすタイミングで解消される
- [ ] M2 Max 側へ新 watchdog (幽霊スペース対策入り) を再配置
- [x] ~~PBP 右側(0x7E) の KVM 連動可否調査~~ — 調査済。OSD の PBP swap は 0x60 と 0x7E の値交換のみで、DDC から 1 コマンドで発火できる trigger VCP は存在しない (3 snapshot 比較と 0xE4/0xE8 の write テストで確認)。KVM 連動機能も意図 (PBP 左は固定したい) と合わず。現行の `sub_set_verified 0x7E` + `sub_set_verified 0x60` の 2 連打が最適解。
