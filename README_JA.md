<h1 align="center">
  <img src="./docs/assets/icon.png" alt="HyperCapslock" width="96" /><br/>
  HyperCapslock
</h1>

<p align="center">
  <b>Caps Lock 本来の機能を残したまま、システム全体で使える vim 風ナビゲーションレイヤーに変えます。</b>
</p>

<p align="center">
  <a href="README.md">🇺🇸 English</a> •
  <a href="README_CN.md">🇨🇳 中文</a> •
  <b>🇯🇵 日本語</b> •
  <a href="README_DE.md">🇩🇪 Deutsch</a>
</p>

<p align="center">
  <a href="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml"><img src="https://github.com/XueshiQiao/HyperCapslock/actions/workflows/build.yml/badge.svg" alt="Build" /></a>
  <a href="https://github.com/XueshiQiao/HyperCapslock/releases/latest"><img src="https://img.shields.io/github/v/release/XueshiQiao/HyperCapslock" alt="Release" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3.0-blue" alt="License" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white" alt="macOS 14+" />
</p>

## コンセプト

Caps Lock はホームポジションのすぐそばにあるのに、使われる場面はあまり多くありません。HyperCapslock はこれを **F18**（どのキーボードにも物理的に存在しないキー）に再マッピングし、OS レベルで F18 + 他のキーの組み合わせをインターセプトして、ナビゲーション・編集・入力ソースの切り替え・シェルコマンドをシミュレートします。

F18 は本物の修飾キー（Cmd・Ctrl・Shift・Alt のいずれでもない）ではないため、**これらの修飾キーとそのまま併用できます**：

| 組み合わせ | 動作 |
|-----------|------|
| `Caps + H` | ← 左へ移動 |
| `Caps + Shift + H` | ← 左へ選択 |
| `Caps + Alt + H` | ← 1 単語分 左へ移動 |
| `Caps + Shift + Alt + H` | ← 1 単語分 左へ選択 |

追加設定は不要です。システムの修飾キーはそのまま通ります。

Caps Lock を**軽く押して**何も押さずに離した場合は、これまで通り Caps Lock のオン/オフを切り替えます。

## デフォルトのキーマッピング

すべてのマッピングは GUI からカスタマイズできます。以下はデフォルト値です：

### ナビゲーション（vim 風）

| 組み合わせ | 動作 |
|-----------|------|
| `Caps + H / J / K / L` | ← ↓ ↑ → 矢印キー |
| `Caps + A` | Home（行頭） |
| `Caps + E` | End（行末） |
| `Caps + Y` | 前の単語 |
| `Caps + P` | 次の単語 |
| `Caps + U` | 10 行 上へ |
| `Caps + D` | 10 行 下へ |

### 編集

| 組み合わせ | 動作 |
|-----------|------|
| `Caps + I` | Backspace |
| `Caps + O` | 下に新しい行（End + Enter） |
| `Caps + N` | `""""""` を挿入してカーソルを中央に配置 |

### 入力ソースの切り替え（macOS）

| 組み合わせ | 動作 |
|-----------|------|
| `Caps + ,` | ABC（英語）に切り替え |
| `Caps + .` | 中国語入力に切り替え |

### シェルコマンド

`Caps + Shift + [キー]` は、GUI から任意のシェルコマンドを実行するようにバインドできます。

## インストール（macOS）

### Homebrew

```bash
brew install --cask XueshiQiao/tap/hypercapslock
```

または [GitHub Releases](https://github.com/XueshiQiao/HyperCapslock/releases) から `.dmg` をダウンロードしてください。

### 権限

このアプリには **アクセシビリティ（Accessibility）** の権限が必要です。
`システム設定 → プライバシーとセキュリティ → アクセシビリティ`

## スクリーンショット

<div align="center">
  <img src="./docs/assets/HyperCapslock.png" width="400" />
</div>

## なぜ Karabiner-Elements ではないのか？

[Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) は 21k 以上のスターを持つ強力なツールで、私自身も長年使ってきました。しかし「Caps Lock をナビゲーションレイヤーにする」という具体的なユースケースに限って言えば：

- **設定の複雑さ** — Karabiner では、ちょっと凝った再マッピングをするのに JSON を手で書く必要があります。HyperCapslock はクリック操作の GUI を備えています。
- **常駐プロセスと負荷** — Karabiner はカーネル拡張と複数のバックグラウンドプロセスをインストールします。HyperCapslock は単一の軽量なネイティブ macOS アプリです。
- **修飾キーの問題** — Karabiner は通常、Caps Lock を本物の修飾キーの組み合わせ（例：Ctrl+Shift+Cmd+Opt）にマッピングします。この「ハイパーキー」方式は機能しますが、既存のショートカットと衝突することがあります。HyperCapslock は F18 にマッピングするため、既存のショートカットと衝突しにくく、本物の修飾キーともそのまま併用できます。

Karabiner のフルパワー（アプリごとのルール、マウスの再マッピング、デバイス別プロファイル）が必要なら、Karabiner を使ってください。最小限のセットアップで、どこでも vim ナビゲーションが使えればよいのであれば、こちらのほうがシンプルな選択肢かもしれません。

## 仕組み

Caps Lock は OS レベルで `hidutil` により F18 に再マッピングされます。続いてアプリは HID レベルで `CGEventTap` を設置します。これは、どのアプリよりも先にキーイベントをインターセプトする、システム全体のイベントタップです。

F18 が押された状態で別のキーが押されると、アプリは元のイベントを破棄し、再マッピング後のキー（例：矢印キー）をシステムの入力ストリームに送ります。注入されたイベントには、フィードバックループを防ぐためのフラグが付与されます。

状態の追跡には、ロックで保護されたランタイム状態（`OSAllocatedUnfairLock` / `NSLock`）を使い、タップスレッド・タイマースレッド・UI 間のスレッド安全性を確保しています。フックのコールバックは、入力の遅延を生まないよう、整数比較と早期リターンといった最小限の処理しか行いません。

技術的な詳細については [how_does_it_work.md](how_does_it_work.md) を参照してください。

## 技術スタック

- **ネイティブ macOS** — SwiftUI + AppKit、Swift 5 言語モード、macOS 14+
- F18 への再マッピングに CoreGraphics `CGEventTap` + `hidutil`、CapsLock の状態取得に IOKit、入力ソースの切り替えに Carbon TIS
- 自動更新に [Sparkle](https://sparkle-project.org)、YAML 設定の解析に [Yams](https://github.com/jpsim/Yams)
- 単一の軽量なネイティブプロセス

## 開発

### 前提条件

- macOS 14+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）

### セットアップ

```bash
git clone https://github.com/XueshiQiao/HyperCapslock.git
cd HyperCapslock
brew install xcodegen
xcodegen generate
open HyperCapslock.xcodeproj   # Cmd+R でビルド＆実行
```

Xcode プロジェクト設定の正本は `project.yml` だけです。変更したら `xcodegen generate` を実行してください。

### ビルド

```bash
xcodebuild -project HyperCapslock.xcodeproj -scheme HyperCapslock -configuration Release build
```

## トラブルシューティング

- **ホットキーが効かなくなった**：ログは `/tmp/hypercapslock-macos.log` に書き込まれます。「アクセシビリティ」権限からアプリを一度削除して追加し直し、アプリを再起動してみてください。
- **ゲーミングモード（Gaming Mode）**：メニューバーアイコンから一時停止/再開することで、すべての再マッピングを一時的に無効化できます。

## ライセンス

GPL v3.0 — [LICENSE](LICENSE) を参照してください。
