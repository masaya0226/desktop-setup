# Mission Control が開かない原因を macOS の Spaces 構成から突き止める

ある日突然、Mission Control が開かなくなった。3本指スワイプもキーボードショートカットも無反応。おまけにフルスクリーンにしていたアプリのスペースにも切り替えられない。通常のデスクトップ間の移動はできる。

再起動すれば直るのは分かっている。でも「なぜ起きたか」が分からないと、また同じことが起きる。

結論から言うと、**存在しないディスプレイのエントリが Spaces 構成に残っていた**のが原因だった。そしてそれを作ったのは、自分で書いたディスプレイ自動化スクリプトの、しかも**3日前に入れた「修正」**だった。

この記事では、macOS の Spaces 管理データを直接読んで原因に辿り着くまでと、再発防止をどう設計したかを書く。マルチモニタの自動化をしている人には応用が効くはず。

---

## 体感から入ると外れる

最初の手がかりは「cmux（ターミナル）を使っている時に起きやすい気がする」という体感だった。ここから素直に入ると、まず疑いたくなるのは次の2つになる。**どちらも外れたのだが、潰し方自体は知っておく価値がある。**

### 仮説1: ターミナルがキーを奪っている

Mission Control は `Ctrl+↑`、スペース移動は `Ctrl+←/→`。tmux 系のターミナルがペイン移動に使う定番のキーと丸かぶりしている。アプリがキーを消費していれば、**そのアプリにフォーカスがある間だけ** Mission Control が効かない。「cmux を使っている時に起きやすい」という体感と綺麗に噛み合う。

確認は設定ファイルを読むだけでいい。

```bash
grep -niE "keybind|shortcut|ctrl" ~/.config/cmux/cmux.json
```

結果は全行コメントアウトされたテンプレートで、カスタムキーバインドは未設定だった。**外れ。**

### 仮説2: Secure Input が掴まれっぱなし

これはターミナル系で本当によくある。パスワード入力欄などで有効化される Secure Input を、アプリが解除し忘れて放置すると、**システム全体のホットキーが巻き添えで効かなくなる**。Mission Control も止まる。

```bash
ioreg -l -w 0 | grep "kCGSSessionSecureInputPID"
```

出力が空なら誰も掴んでいない。今回は空。**外れ。**

> ちなみに掴んでいるプロセスがいる場合はここに PID が出るので、犯人を直接特定できる。覚えておくと便利。

### 入力側がシロだと確定させる

念のため、ショートカット設定そのものも確認する。macOS のシステムショートカットは `com.apple.symbolichotkeys` に**数値 ID** で格納されている。主要なものはこれ。

| ID | 機能 |
|---|---|
| 32 | Mission Control |
| 33 | アプリケーションウインドウ |
| 79 / 81 | 左 / 右のスペースへ移動 |
| 118〜121 | デスクトップ 1〜4 へ切り替え |

```bash
defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys
```

該当 ID はすべて `enabled = 1` だった。

ここまでで **「キーを押す側」は全部シロ**と分かる。だとすれば壊れているのは、押された後に動く Spaces そのものだ。

**体感は調査の入口としては優秀だが、出口にしてはいけない。** 「cmux で起きやすい」は結果的に正しかったが、理由は全く別のところにあった（後述）。

---

## Spaces 構成を直接読む

macOS のスペース構成は `com.apple.spaces` に入っている。plist なので Python で読むのが早い。

```python
import subprocess, plistlib

out = subprocess.run(['defaults', 'export', 'com.apple.spaces', '-'],
                     capture_output=True).stdout
d = plistlib.loads(out)
md = d['SpacesDisplayConfiguration']['Management Data']

for mon in md['Monitors']:
    cur = mon.get('Current Space')
    print(mon.get('Display Identifier'),
          '| Current Space:', cur and cur.get('ManagedSpaceID'))
```

出力がこれだった。

```
Main                                    | Current Space: 25
4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20    | Current Space: 6
21CAEADE-7B6E-452D-968E-0A92335B031E    | Current Space: None
```

**3件ある。でも実際に繋がっているディスプレイは2台。**

3つ目の `21CAEADE-…` は `Current Space` を持たず、`Spaces` 配列も空。完全な残骸だ。BetterDisplay に問い合わせても、この UUID は存在しない。

```bash
BD=/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay
$BD get -identifiers | grep -c "21CAEADE"   # → 0
```

### なぜこれで Mission Control が死ぬのか

Mission Control は**全ディスプレイの current space を列挙してから**合成アニメーションを組む。current space が nil のエントリが1つでも混ざれば、その時点で組み立てに失敗する。

フルスクリーンスペースに切り替えられないのも同根だ。フルスクリーンのスペース（plist 上は `type=4`）は特定のディスプレイに強く紐づくので、ディスプレイ側の識別が壊れると行き先を見失う。

**「cmux を使っている時に起きやすい」の正体もここにある。** cmux は常にフルスクリーンで使っていた。つまり cmux が犯人なのではなく、**cmux が最も壊れやすい場所（フルスクリーンスペース）に常駐していたから、被害が真っ先に見えた**だけだった。体感は現象を正しく捉えていたが、因果は逆向きだったことになる。

---

## 幽霊はどこから来たのか

ここで自分のディスプレイ自動化スクリプトに話が戻る。

2台の Mac と 2台のモニタを1つのキーで切り替える仕組みを組んでいて、その中で BetterDisplay の `connected` を制御している。

```bash
$BD set -uuid=<UUID> -connected=off
```

これは**論理的な接続状態**を切り替えるもので、`off` にすると macOS からはそのディスプレイが**物理的に消えたように見える**。ウィンドウが見えない画面に取り残されるのを防ぐために使っていた。

そしてもう1つ、この仕組みには既知の厄介事があった。**BetterDisplay の UUID は不変ではない。** TB/DP の再列挙で `portID` が変わると、BD は同じモニタに**別の UUID を採番し直す**。

この2つが噛み合うと、こうなる。

```
1. connected=off の状態（このマシンは非メイン、サブモニタの左側に表示中）
2. その最中に BD が portID 変化で UUID を再採番する
3. watchdog が「新」UUID で connected=on を打つ
4. macOS から見ると
   「旧 UUID の display は消えたまま、新 UUID の display が現れた」
5. 旧 UUID のエントリが Current Space を持たない残骸として永久に残る
```

**`connected` の状態を UUID の世代交代をまたいで持ち越すと幽霊になる。** これが本質だった。

---

## 一番効いた問い: 「なぜ今まで起きなかったのか」

原因が分かった時点で、もう1つ引っかかることがあった。この仕組みは4ヶ月動いていて、UUID の再採番自体も以前から起きていた。**なぜ今回だけ幽霊が生まれたのか。**

git log を辿ると、3日前のコミットに行き当たった。

> `71f67e6` ディスプレイ識別を UUID ハードコードから EDID シリアルの動的解決へ

UUID をハードコードしていたのをやめ、EDID のシリアル番号から毎回引き直す方式に変えた修正だ。これは**別の障害を直すための、それ自体は正しい修正**だった。UUID が再採番されると切替が全停止する問題を解消している。

だが、修正の前後で watchdog の挙動は次のように反転していた。

| | 修正前（UUID ハードコード） | 修正後（動的解決） |
|---|---|---|
| BD が UUID を振り直したら | `Failed.` を返して**何もしなくなる** | シリアルから引き直して**追従する** |
| 切替機能 | 全停止（これが直したかった障害） | 正常動作 |
| `connected` トグル | 巻き添えで止まっていた | **再び動き出した** |
| Spaces への影響 | 発生しない | **新旧 UUID の付け外しとして記録され、残骸が溜まる** |

つまり**修正前は「壊れていたおかげで幽霊が生まれなかった」**。動的解決によって書き込み経路が復活し、同時に幽霊を作る経路も復活した。

これは責めるべきバグではなく、**片方の障害を直したら、それに隠されていたもう一方が顔を出した**という構図だ。「直したはずなのに新しい問題が出た」時、直した内容が悪いとは限らない。**それまで何を止めていたのか**を見るほうが早い。

---

## 掃除しようとして分かったこと

原因が分かったので残骸を消しにいく。ここでもう1つハマった。

### `killall Dock` — 一時的にしか効かない

```bash
killall Dock
```

Mission Control は**動くようになった**。これで解決かと思ったが、もう一度 plist を読むと `21CAEADE-…` はしっかり残っていた。

Dock はメモリ上の構成を組み直すので表示は復旧する。だが残骸自体は消えていないので、次の Spaces 再配置でまた壊れる。**症状が消えたことを解決と取り違えると、数日後に同じ調査をやり直す羽目になる。**

### plist を直接編集 — 効かない

`com.apple.spaces.plist` から該当エントリを消しても戻される。**WindowServer がメモリ上に構成を保持していて、plist はその写しにすぎない**からだ。

### ログアウト → 再ログイン — これが正解

WindowServer のユーザーセッションごと作り直されるので、実在しないディスプレイのエントリは落ちる。

| 方法 | 効果 |
|---|---|
| `killall Dock` | 応急処置。表示は復旧するが**残骸は残り再発する** |
| plist を直接編集 | 効かない。WindowServer に上書きされる |
| **ログアウト → 再ログイン** | **恒久的に解消** |

---

## 再発防止をどう設計したか

UUID の再採番自体は止められない（ケーブルや KVM の都合で起きる）。なので**予防・検出・診断の3層**で構えた。

### 予防: 世代交代の直後は `connected` を触らない

`resolve_display_uuids()` をそのまま呼ぶのをやめ、**前回の UUID と比較するラッパー**を通す。

```bash
resolve_and_track() {
  resolve_display_uuids || return 1

  if [ -n "$PREV_MAIN" ] && { [ "$MAIN_UUID" != "$PREV_MAIN" ] || [ "$SUB_UUID" != "$PREV_SUB" ]; }; then
    log "UUID 世代交代を検知: main ${PREV_MAIN} -> ${MAIN_UUID}"
    notify "BetterDisplay が UUID を再採番しました。..."
    settle_left=$SETTLE_CYCLES        # 数周期のあいだ connected を触らない
  fi

  PREV_MAIN=$MAIN_UUID
  PREV_SUB=$SUB_UUID
  save_prev_uuids
  return 0
}
```

ポイントは2つある。

**1. 解決に失敗したら `PREV_*` を上書きしない。** BD host が落ちているだけの一時的な読み取り失敗を「世代交代」と誤認しないため。次に引けた時に正しく比較できる状態を保つ。

**2. これは幽霊をゼロにする対策ではない。** `portID` がバタついている最中に何度も付け外しして残骸を量産するのを防ぐだけで、世代交代そのものは止められない。だから検出とセットで運用する必要がある。

### 検出: 幽霊を数える

「`Display Identifier` はあるが `Current Space` がない」エントリを数えればいい。plist をパースする必要すらない。

```bash
count_ghost_spaces() {
  local out ids curs
  out=$(defaults read com.apple.spaces SpacesDisplayConfiguration 2>/dev/null) || { echo 0; return; }
  ids=$(printf '%s\n' "$out"  | grep -c '"Display Identifier"')
  curs=$(printf '%s\n' "$out" | grep -c '"Current Space"')
  [ "$ids" -gt "$curs" ] && echo $(( ids - curs )) || echo 0
}
```

生きているディスプレイだけが `Current Space` を持つので、**差分がそのまま幽霊の数**になる。`defaults` と `grep` だけなので python の起動すら要らない。4秒ループの常駐プロセスに入れるならこの軽さは効く（それでも毎周期は重いので、実際は60周期に1回に間引いている）。

### 診断: 人間が読む用のスクリプトを別に用意する

常駐プロセスの通知とは別に、`bash scripts/check-spaces-health.sh` で構成を目視できるようにした。

```
  ✅ Main
      Current Space id=3 / Spaces 4 件
        - デスクトップ   id=3
        - フルスクリーン id=42  (Google Chrome, pid 884)
        - フルスクリーン id=25  (cmux, pid 2640)
  👻 21CAEADE-7B6E-452D-968E-0A92335B031E
      Current Space なし / Spaces 0 件  ← 幽霊エントリ
```

**フルスクリーンスペースの所有プロセス名まで出す**のがコツで、「どのアプリのスペースが飛んだか」が一目で分かる。Mission Control 系ホットキーの `enabled` 状態も併記して、最初に潰した「入力側がシロか」の切り分けを毎回やり直さずに済むようにした。

### 診断メッセージで気をつけたこと

最初、診断スクリプトにこう書いていた。

> Mission Control が開かない症状が出ていれば、原因はこれです。

だがこれは**正確ではない**。`killall Dock` の直後は、幽霊が残っていても Mission Control は動く。断定すると「幽霊があるのに動くじゃないか」となって、逆に判断を誤らせる。

こう直した。

> 幽霊がある = 即座に壊れる、ではありません。Dock を再起動するとメモリ上の構成が組み直されて一時的に動きます。ただし残骸が残る限り次の再配置で再発します。

**診断ツールは、症状と原因の関係を実態どおりに書かないと、次に読む自分を騙す。**

---

## まとめ

- **入力側から順に潰す** — ショートカット設定（`com.apple.symbolichotkeys`）、Secure Input（`ioreg | grep kCGSSessionSecureInputPID`）、アプリのキーバインド。ここがシロなら、壊れているのは Spaces 側
- **Spaces 構成は `com.apple.spaces` で直接読める** — `Monitors` の各要素が `Current Space` を持たなければ幽霊
- **Mission Control は全ディスプレイの current space を列挙して合成する** — nil が1つ混ざるだけで起動できない
- **`connected` の on/off は macOS にとって物理的な抜き差しと同じ** — Spaces 再配置が走る
- **`connected` の状態を UUID 世代交代をまたいで持ち越すと幽霊になる** — 旧 UUID のエントリが取り残される
- **「直したのに新しい問題が出た」時は、それまで何を止めていたのかを見る** — 今回は動く方向に直したことで、止まっていた副作用の経路まで復活した
- **幽霊は `killall Dock` でも plist 編集でも消えない** — WindowServer がメモリ上に構成を持つ。ログアウト → 再ログインが必要
- **症状が消えることと解決することは違う** — `killall Dock` で表示は戻るが残骸は残る
- **幽霊の検出は `defaults` + `grep -c` で足りる** — `Display Identifier` の数と `Current Space` の数の差
- **診断ツールの文言は実態どおりに** — 断定しすぎると次の自分を騙す
