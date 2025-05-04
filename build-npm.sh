#!/usr/bin/env sh
wails3 generate bindings -ts -d npm-package/bindings &&
    tsc -t es2022 -m es2022 --declaration --outDir npm-package/dist npm-package/index.ts &&
    npm pack ./npm-package/dist

rm -rf npm-package/dist/*.js npm-package/dist/*.d.ts
