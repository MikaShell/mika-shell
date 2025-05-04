# NPM Package

1. `wails3 generate bindings -ts -d npm-package/bindings`
2. `cd npm-package`
3. `tsc -t es2022 -m es2022 --declaration --outDir dist npm-package/index.ts`
4. `npm pack ./dist`
