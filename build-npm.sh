#!/usr/bin/env sh
if [ "$1" = "core" ]; then
    tsc -t es2022 -m es2022 --declaration --emitDeclarationOnly --outDir npm-package/output/core npm-package/core/index.ts
    cp npm-package/core/index.js npm-package/output/core/index.js
    cp npm-package/core/package.json npm-package/output/core/package.json
elif [ "$1" = "extra" ]; then
    ./build-npm.sh core
    tsc -t es2022 -m es2022 --module NodeNext --declaration --outDir npm-package/output/extra npm-package/extra/index.ts
    cp npm-package/extra/package.json npm-package/output/extra/package.json
else 
    echo "Invalid argument, please use either 'core' or 'extra'"
fi

if [ $? -ne 0 ]; then
    exit 1
fi

if [ "$2" = "pack" ]; then
    npm pack ./npm-package/output/$1
    rm -rf npm-package/output
fi
