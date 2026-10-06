import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs/promises';
let source=await fs.readFile(new URL('../cloudkit-worker.js',import.meta.url),'utf8');source=source.replace(/^import .*;\n/gm,'');source += '\nexport {paidOffer,readPetAssistPayment};';
const mod=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
const fields=amount=>({paymentAmount:{value:'$'+amount},paymentStatus:{value:'Payment requested'},requestedService:{value:'Marketplace'}});
test('Marketplace prices require a trusted record and confirmed booking',()=>{
 assert.equal(mod.paidOffer({recordName:'petassist-'+'a'.repeat(32),fields:fields(39),marketplace:true,visitStatus:'accepted'}).amount,'39.00');
 assert.equal(mod.paidOffer({recordName:'petassist-'+'a'.repeat(32),fields:fields(39),visitStatus:'accepted'}),null);
 assert.equal(mod.paidOffer({recordName:'petassist-'+'a'.repeat(32),fields:fields(39),marketplace:true,visitStatus:'cancelled'}),null);
 assert.equal(mod.paidOffer({recordName:'careline-test',fields:fields(39),marketplace:true}),null);
});
test('Existing payments stay unchanged; unknown and changed amounts fail closed',async()=>{
 const originalFetch=globalThis.fetch;let record={recordName:'petassist-'+'a'.repeat(32),serviceID:'nailTrim',fields:fields(35)};
 const stub={fetch:async()=>Response.json(record)},env={PETASSIST_PAYMENTS:{idFromName:n=>n,get:()=>stub}};
 globalThis.fetch=async()=>{throw Error('No network allowed')};assert.equal((await mod.readPetAssistPayment(env,record.recordName)).fields.paymentAmount.value,'$35');
 record={...record,marketplace:true};globalThis.fetch=async()=>Response.json({token:'a'.repeat(32),serviceID:'nailTrim',amount:'39.00',visitStatus:'accepted'});assert.equal(await mod.readPetAssistPayment(env,record.recordName),null);
 globalThis.fetch=async()=>Response.json({token:'a'.repeat(32),serviceID:'nailTrim',amount:'35.00',visitStatus:'cancelled'});assert.equal((await mod.readPetAssistPayment(env,record.recordName)).visitStatus,'cancelled');globalThis.fetch=originalFetch;
});
