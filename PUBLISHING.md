# Publishing Guide

## Before publishing

Run from the package root:

```bash
npm run smoke-test
bash ./scripts/helper-runtime-capability-test.sh
bash ./scripts/helper-packaging-smoke-test.sh
npm run release-check
```

Those direct verifier entrypoints self-isolate the repo-local extension when they shell back into `pi`, so no extra `pi --no-extensions` wrapper is required even if this package is also installed globally on the publishing machine. The two helper probes intentionally pack and extract the package before invoking `pi -e ...`, so source-tree-only success is not treated as sufficient helper-runtime proof.

## GitHub release flow

```bash
git init
git add .
git commit -m "Initial release"
git branch -M main
git remote add origin git@github.com:<YOUR-USER>/pi-letscook.git
git push -u origin main
git tag v0.1.0
git push origin v0.1.0
```

Users can then install with:

```bash
pi install git:github.com/<YOUR-USER>/pi-letscook@v0.1.0
```

## npm release flow

For the scoped public package name `@linimin/pi-letscook`, publish with:

```bash
npm login
npm publish --access public
```

Users can then install with:

```bash
pi install npm:@linimin/pi-letscook
```

## Recommended metadata before public release

Consider updating these fields in `package.json` before publishing publicly:

- `name`
- `repository`
- `homepage`
- `bugs`
- `author`

## Versioning

- bump `version` in `package.json`
- add a new entry to `CHANGELOG.md`
- create a matching git tag like `v0.1.1`
