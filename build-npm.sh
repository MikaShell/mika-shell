#!/usr/bin/env sh
tsc -t es2022 -m es2022 --declaration --emitDeclarationOnly --outDir npm-package bindings/index.ts

if [ "$1" = "pack" ]; then
    npm pack ./npm-package
    rm -rf npm-package/*.d.ts
fi
