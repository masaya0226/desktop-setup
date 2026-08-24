# BetterDisplay の UUID は変わる — ディスプレイ識別をシリアルからの動的解決に作り替える

2台の Mac と 2台の BenQ PD2730S をキーボード一発で切り替える自動化が、ある日突然まるごと動かなくなった。
キーを押しても何も起きない。モニタは正常。BetterDisplay も動いている。

原因は **「BetterDisplay が同じモニタに別の UUID を採番し直していた」** ことだった。
しかも新しい UUID が、スクリプトが別のモニタ用に持っていた定数とたまたま同じ値で、
直し方を間違えると「サブモニタへの命令がメインモニタに飛ぶ」という二次被害が起きる状態だった。

この記事では、その切り分けの手順と、UUID ハードコードをやめて EDID シリアルから
動的解決する設計に作り替えるまでを書く。DDC / BetterDisplay CLI で
マルチモニタ自動化をしている人には応用が効くはず。

---

## 前提: どういう仕組みだったか

- メインモニタ（右）とサブモニタ（左）の 2 枚。サブは PBP で 2 台の Mac を並置できる
- Corne キーボードの F19/F20 → Hammerspoon → bash スクリプト
- スクリプトは **BetterDisplay CLI 経由で DDC の VCP コードを叩く**（`0x60`=入力切替、`0x7D`=PBP、`0x7E`=PBP 右側入力）
- 2台とも同じ型番なので `-name=` では区別できず、**`-uuid=` でモニタを指定していた**

```bash
MAIN_UUID="2DF75969-A2F5-4608-A9B4-429B3A3CA4BB"
SUB_UUID_OFF="B02476A6-81D7-444F-B03B-DC515516025A"
SUB_UUID_ON="4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20"
```

この 3 行が、後で全ての元凶になる。

---

## 症状と第一の観測

キーを押しても無反応。まず生きているものを確認する。

```bash
$ pgrep -lf BetterDisplay
3331 /Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay   # 生きてる
$ launchctl list | grep desktop-watchdog
3310  0  com.masayaabe.desktop-watchdog                              # 生きてる
```

プロセスは全部生きている。ではモニタ側かというと、こちらも正常に映っている。
次に BetterDisplay が何を認識しているかを見る。

```bash
$ BD get -identifiers
{
  "UUID" : "B02476A6-81D7-444F-B03B-DC515516025A",
  "alphanumericSerial" : "GAS00262019",
  "model" : "32908",
  ...
},{
  "UUID" : "4B3EC4EE-1A27-499D-A8A0-DA1F9B545E20",
  "alphanumericSerial" : "E1T00045019",
  "model" : "32907",
  ...
}
```

**`MAIN_UUID` (`2DF75969-…`) が居ない。** 直接叩いても死んでいる。

```bash
$ BD get -uuid=2DF75969-A2F5-4608-A9B4-429B3A3CA4BB -ddc -vcp=0x60
Failed.
```

スクリプトは冒頭でメインモニタの入力値を読んでからトグル方向を決める設計なので、
ここで読めない＝**何もせず abort** する。無反応の理由はこれで説明がついた。

### ここで止まってはいけない

「UUID が変わったから書き換えよう」で終わらせると事故る。
**なぜ変わったのか** と **新しい UUID はどれなのか** を確定させる必要がある。

そして、よく見ると妙なことがある。
ドキュメントには `B02476A6-…` は **「サブモニタ PBP オフ時の UUID」** と書いてあった。
なのに今、`B02476A6-…` と `4B3EC4EE-…`（サブモニタ PBP オン時のはず）が **同時に** 存在している。
同じ 1 枚のモニタが PBP オンとオフを同時にやっているわけがない。

つまり **記録のどこかが間違っている**。

---

## 決定的な証拠は BetterDisplay の設定ファイルにあった

BetterDisplay は過去に見たディスプレイの識別情報を `defaults` に貯めている。
現在つながっているものだけを見せる `-identifiers` と違い、**履歴が残る**。

```bash
defaults read pro.betterdisplay.BetterDisplay > /tmp/bd-prefs.txt
grep -o 'storedIdentifiers@Display:[0-9]*' /tmp/bd-prefs.txt | sort -u
```

中身は JSON がエスケープされて埋まっているので、パースして並べる。

```python
import re, json
raw = open('/tmp/bd-prefs.txt', encoding='utf-8', errors='replace').read()
for m in re.finditer(r'"storedIdentifiers@Display:(\d+)" = "(.*?)";\n', raw, re.S):
    tag, payload = m.group(1), m.group(2)
    s = payload.replace('\\\\"', '"').replace('\\"', '"').replace('\\\\/', '/').replace('\\/', '/')
    for d in json.loads(s):
        print(tag, d.get('systemUUID'), d.get('alphanumericSerialNumber'),
              d.get('modelNumber'), d.get('portID'), d.get('ioDisplayLocation'))
```

結果:

| tagID | UUID | serial | model | portID | ioDisplayLocation |
|---|---|---|---|---|---|
| 10 | `2DF75969-…` | GAS00262019 | 32908 | 2097684**48** | dispext0@8000000 |
| **20** | **`B02476A6-…`** | **GAS00262019** | **32908** | 2097684**64** | **dispext0@8000000** |
| 11 | `4B3EC4EE-…` | E1T00045019 | 32907 | 209768448 | disp0@7C000000 |
| 6 | `37D8832A-…` | — | 41043 | — | disp0@7C000000 (内蔵) |

これで全部つながった。

**tagID 10 と 20 は同じ 1 枚のモニタだ。** シリアルも model も EDID データもバイト単位で一致し、
接続ロケーションまで同じ。**違うのは `portID` が 16 ずれていることだけ。**

BetterDisplay は portID を含めて displays を同定しているらしく、
TB の再列挙で portID がずれた結果、**同じ個体に別 UUID を採番し直した**。

そして `4B3EC4EE-…`（シリアル `E1T00045019`）が本物のサブモニタ。

### 元の記録が間違っていた、が、偶然動いていた

つまり `SUB_UUID_OFF="B02476A6-…"` は最初から誤記で、**実体はメインモニタ**だった。
ではなぜ今まで動いていたのか。`sub_get` の実装を見ると分かる。

```bash
sub_get() {
  val=$($BD get -uuid="$SUB_UUID_OFF" -ddc -vcp=$vcp 2>/dev/null || echo "")
  if [ -z "$val" ]; then
    val=$($BD get -uuid="$SUB_UUID_ON" -ddc -vcp=$vcp 2>/dev/null || echo "")
  fi
  echo "$val"
}
```

当時 `B02476A6-…` は BD の追跡下に無かったので **1 行目が必ず空振りし、
フォールバックで本物のサブモニタに落ちていた**。偶然の正解だ。

ところが今回 `B02476A6-…` が「生きているメインモニタ」として復活したので、
1 行目が成功してしまう。**サブモニタ用の `sub_set` がメインモニタに `0x7D`（PBP）を書く**。
`MAIN_UUID` だけ直していたら、これを踏んでいた。

> 教訓: 「偶然動いていたコード」は、環境が変わった瞬間に **静かに間違った方向に動き出す**。
> フォールバックは便利だが、失敗を握りつぶすぶん誤りの発覚を遅らせる。

### 契機はおそらくアプリ更新

```bash
$ stat -f "%Sm %N" /Applications/BetterDisplay.app
Aug 15 21:31:16 2026 /Applications/BetterDisplay.app
```

「最近おかしい」という体感と一致した。断定はできないが、
**UUID は環境更新で変わりうる** という事実だけで設計を変えるには十分だ。

---

## 対策: UUID をやめてシリアルで引く

`portID` で変わってしまう UUID は、識別子として不適格だった。
代わりに使えるものを比較する。

| 候補 | portID 変化に耐えるか | PBP に耐えるか | 両 Mac で共通か | 判定 |
|---|---|---|---|---|
| `UUID` | ❌ 今回まさに変わった | ? | ❌ Mac ごとに別値 | 不可 |
| `registryLocation` | ⭕ | ⭕ | ❌ ポート依存 | 惜しい |
| `alphanumericSerial` | ⭕ EDID 由来 | ⭕ | ⭕ モニタ個体固有 | **採用** |
| `model` | ⭕ | ⭕ | ⭕ | 2台の型番が違えば可 → 予備キー |

今回は幸い 2 台の model 番号が `32908` / `32907` と異なっていたので、
**シリアルを第一キー、model を第二キー**にできた。
第二キーを用意したのは、BD が EDID を読めず `Generic Display` 扱いで登録した痕跡
（`tagID 16`, model だけ持っていた）が履歴に残っていたためだ。

```bash
MAIN_SERIAL="GAS00262019"; MAIN_MODEL="32908"   # メインモニタ (右)
SUB_SERIAL="E1T00045019";  SUB_MODEL="32907"    # サブモニタ (左, PBP)
```

**シリアルは EDID 由来なので、どちらの Mac から見ても同じ値になる。**
結果として、2台分のスクリプトで識別子の定数が完全に共通化できた。

### bash だけで `-identifiers` をパースする

ここで python や jq を呼びたくなるが、避けた理由がある。
このプロジェクトの watchdog は **launchd から起動される**。
launchd 配下は TCC の制約が厳しく、依存を増やすほど「手元では動くのに常駐だと動かない」を踏む。
`/usr/bin/python3` も Command Line Tools が入っていない環境ではインストールダイアログを出しうる。

なので **外部依存ゼロの bash だけ**で書く。
`-identifiers` の出力は「1 行 1 キー」「オブジェクトの先頭が `{` か `},{`」という素直な形なので、
行単位のステートマシンで足りる。

```bash
bd_uuid_by_field() {
  local field=$1 want=$2 uuid="" line val
  while IFS= read -r line; do
    case "$line" in
      '{'|'},{') uuid="" ;;          # オブジェクト境界でリセット
    esac
    case "$line" in
      *'"UUID"'*)
        val=${line#*: \"}; uuid=${val%\"*} ;;
      *"\"$field\""*)
        val=${line#*: \"}; val=${val%\"*}
        if [ "$val" = "$want" ] && [ -n "$uuid" ]; then
          printf '%s\n' "$uuid"
          return 0
        fi ;;
    esac
  done < <($BD get -identifiers 2>/dev/null)
  return 1
}
```

パラメータ展開のところだけ補足しておく。行は `  "UUID" : "B024…",` の形をしている。

- `${line#*: \"}` … 先頭から最短で `: "` までを削る → `B024…",`
- `${val%\"*}` … 末尾から最短で `"` 以降を削る → `B024…`

末尾のカンマの有無どちらでも同じ結果になるのが嬉しいところ。

そして 2 枚まとめて解決する。

```bash
resolve_display_uuids() {
  MAIN_UUID=$(bd_uuid_by_field alphanumericSerial "$MAIN_SERIAL") \
    || MAIN_UUID=$(bd_uuid_by_field model "$MAIN_MODEL") \
    || MAIN_UUID=""
  SUB_UUID=$(bd_uuid_by_field alphanumericSerial "$SUB_SERIAL") \
    || SUB_UUID=$(bd_uuid_by_field model "$SUB_MODEL") \
    || SUB_UUID=""
  [ -n "$MAIN_UUID" ] && [ -n "$SUB_UUID" ] && [ "$MAIN_UUID" != "$SUB_UUID" ]
}
```

最後の行が地味に大事で、**「両方引けて、かつ別物である」ことを成功条件にしている**。
片方しか引けない状態や、フォールバックで両方が同じ UUID に解決されてしまった状態で
先へ進むと、まさに今回踏みかけた「サブへの命令がメインに飛ぶ」事故になる。**曖昧なら止める。**

### 副産物: 危険な復旧手段を捨てられた

旧実装は UUID が失われたときの復旧に `BD perform -reconfigure`（GUI の Redetect Displays）を
使っていたが、これには 2 つの問題があった。

1. 生きている UUID まで追跡解除してしまうことがある
2. 並列 DDC 書き込みと重なると BD 本体が固まる

そのため直前のバージョンでは「自動呼び出しを無効化し、失敗したら諦めて abort」になっていた。
これが今回、**復旧の芽を完全に潰していた**（UUID lost → 即 abort）。

動的解決を入れると、この復旧手段は素直に置き換えられる。

```bash
main_get_input() {
  for _ in 1 2 3 4 5; do
    val=$($BD get -uuid="$MAIN_UUID" -ddc -vcp=0x60 2>/dev/null || echo "")
    [ -n "$val" ] && { echo "$val"; return 0; }
    sleep 1
  done
  if resolve_display_uuids; then     # ← reconfigure ではなく引き直し
    for _ in 1 2 3; do ... done
  fi
  return 1
}
```

`resolve_display_uuids` は **読むだけで副作用がない**。
BD の状態を壊さないし、まさに起きた障害（UUID が変わった）をピンポイントで直せる。
「乱暴な万能リセット」より「起きた障害に対応する狭い復旧」のほうが強い、という good example になった。

---

## 実測で見つかったリグレッション

直したつもりで終わらせず、**状態を変えない検証**をした。
現在値をそのまま書き戻せば、書き込み経路と read-back 経路を安全に通せる。

```bash
cur_7e=$(sub_get 0x7E)
sub_set_verified 0x7E "$cur_7e"   # 同じ値を書く = 状態は変わらない
```

その直後の読み出しでこうなった。

```
後: main 0x60=21  sub 0x7D= 0x60= 0x7E=2
```

`0x7D` と `0x60` が空、そして `0x7E` が `2`（本来 `0x7D` が返すべき値）。**値がずれている。**

原因は DDC の既知の癖で、**書き込み直後の数秒はバスが不安定**というもの。
（間隔を空けて読み直したら `0x7D=2 0x60=15 0x7E=21` と正常だった。状態は壊れていなかった）

問題は、旧 `sub_get` が **2 つの UUID を順に試すことで実質リトライになっていた**のに、
単一 UUID に整理した結果 **その暗黙のリトライを失っていた**こと。明示的に戻す。

```bash
sub_get() {
  local vcp=$1 val
  for _ in 1 2 3; do
    val=$($BD get -uuid="$SUB_UUID" -ddc -vcp=$vcp 2>/dev/null || echo "")
    [ -n "$val" ] && { echo "$val"; return 0; }
    sleep 1
  done
  echo ""
  return 1
}
```

> 教訓: **冗長に見えるコードを整理するときは、それが偶然担っていた役割を疑う。**
> 今回は「間違った UUID への無駄な問い合わせ」が、実は「リトライ」と「待ち時間」を兼ねていた。

---

## 診断スクリプトを置いておく

同じことが起きたときに 5 分で切り分けられるよう、診断を 1 コマンドにした。

```bash
$ bash scripts/resolve-displays.sh
=== BD host ===
  running (pid 3331)

=== BD が現在追跡しているディスプレイ ===
  "UUID" : "4B3EC4EE-…",  "alphanumericSerial" : "E1T00045019",  "model" : "32907", ...
  "UUID" : "B02476A6-…",  "alphanumericSerial" : "GAS00262019",  "model" : "32908", ...

=== 解決結果 ===
  OK
  MAIN (serial GAS00262019 / model 32908) → B02476A6-…
  SUB  (serial E1T00045019 / model 32907) → 4B3EC4EE-…

=== DDC 実測 ===
  MAIN: connected=on  main=true  0x60=21
  SUB:  connected=on  0x7D=2  0x60=15  0x7E=21
```

「BD 本体は生きているか」「2 枚とも引けているか」「DDC は通るか」が一画面で分かる。
**障害時にまず見る画面を用意しておく**のは、自動化そのものと同じくらい価値がある。

---

## まとめ

- **BetterDisplay の UUID は不変ではない。** `portID` が変わると同一個体に別 UUID が採番される。ハードコードしてはいけない
- 識別には **EDID 由来の `alphanumericSerial`** を使う。ポートにも PBP にも接続先 Mac にも依存しない
- EDID が読めない場合に備えて **`model` を第二キー**に。ただし **曖昧なら止める**（両方引けて別物、を成功条件に）
- `defaults read pro.betterdisplay.BetterDisplay` の **`storedIdentifiers` には履歴が残る**。「今の状態」ではなく「変化」を見たいときの一次資料になる
- **フォールバックは誤りを隠す。** 「なぜか動いていた」コードは環境変化で静かに壊れる方向に転ぶ
- **冗長なコードを整理するときは、それが偶然担っていた役割を疑う**（無駄な問い合わせ = リトライだった）
- 復旧手段は **副作用の小さいものを選ぶ**。`reconfigure` のような万能リセットより、起きた障害を直す狭い操作のほうが強い
- 破壊的な操作を伴う検証は、**同値書き戻し**で経路だけ通す手がある
