# spec-runner の npm 公開手順

## 1. コミット

```bash
git add .
git commit -m "your message"
```

## 2. GitHub にプッシュ

```bash
git push -u origin main
```

## 3. npm に公開

### 初回のみ

- [npmjs.com](https://www.npmjs.com) で 2FA を有効化（Account → Two-Factor Authentication）
- または [Tokens](https://www.npmjs.com/settings/~/tokens) で Publish 権限のトークンを発行し、`npm login` でパスワードの代わりにトークンを入力

### 公開コマンド

```bash
npm publish --access public
```

- 2FA 有効時: ブラウザで認証 URL が開く → 認証後、ターミナルで Enter

### package.json の事前チェック（任意）

```bash
npm pkg fix
```

- `repository.url`: `git+https://github.com/USER/REPO.git` 形式
- `bin`: パスは `bin/spec-runner.js`（`./` なしでも可）

## 4. バージョンアップして再公開

```bash
npm version patch   # 1.0.0-alpha.1 → 1.0.0-alpha.2
npm publish --access public
```

---

**確認**: https://www.npmjs.com/package/spec-runner  
**利用**: `npx spec-runner` または `npm install -g spec-runner`
