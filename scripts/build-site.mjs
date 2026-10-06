import { mkdir, copyFile, cp } from 'node:fs/promises';
const root = new URL('../', import.meta.url);
const output = new URL('site-dist/', root);
await mkdir(new URL('docs/', output), { recursive: true });
for (const name of ['conversation.html','conversation.css','conversation.js','index.html','privacy.html','terms.html','welcome.html','poster.html','operator.html','sw.js','manifest.webmanifest']) {
  await copyFile(new URL(name, root), new URL(name, output));
}
await cp(new URL('icons/', root), new URL('icons/', output), { recursive: true });
await copyFile(new URL('docs/share-qr.png', root), new URL('docs/share-qr.png', output));
console.log('Built static care-line website in site-dist/');
