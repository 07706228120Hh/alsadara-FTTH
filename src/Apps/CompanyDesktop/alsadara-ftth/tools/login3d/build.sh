#!/usr/bin/env bash
# يبني assets/login3d/city.html من scene.js + template.html (ملف واحد يعمل بلا إنترنت).
# المتطلبات: Node.js. التشغيل من مجلد tools/login3d:  bash build.sh
set -e
cd "$(dirname "$0")"
[ -d node_modules/three ] || npm i three@0.160.0 esbuild@0.20.2
npx esbuild scene.js --bundle --minify --format=iife --target=es2019 --outfile=bundle.js
node -e "const fs=require('fs');const t=fs.readFileSync('template.html','utf8');const b=fs.readFileSync('bundle.js','utf8');fs.writeFileSync('../../assets/login3d/city.html',t.replace('__BUNDLE__',()=>b));console.log('assets/login3d/city.html', (fs.statSync('../../assets/login3d/city.html').size/1024|0)+' KB')"
