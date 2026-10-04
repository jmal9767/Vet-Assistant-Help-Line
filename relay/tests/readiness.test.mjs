import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

const source = (await readFile(new URL('../cloudkit-worker.js', import.meta.url),'utf8')).replace(/^import .*;$/m,'const applePayDomainAssociation = "association";').replace('export default {','const worker = {').replace('export class PetAssistPayments','class PetAssistPayments');
const key=await webcrypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const pem=Buffer.from(await webcrypto.subtle.exportKey('pkcs8',key.privateKey)).toString('base64');
const fixture={name:'Release test',email:'release@example.invalid',phone:'5555555555',species:'Dog',sex:'Unknown',reproductiveStatus:'Unknown',category:'Other',symptomOnset:'General question',symptomTrend:'Not applicable / general question',appetite:'Normal',drinking:'Normal',urination:'Normal',stool:'Normal',energy:'Normal',vomiting:'None',question:'How can I provide enrichment?',requestedService:'Quick Question — Email · $10',paymentMethod:'PayPal or Apple Pay',signedConsentName:'Release test',signedConsentAt:'2026-10-04T16:00:00Z',acceptedTerms:'yes',acceptedCommunicationPolicy:'yes'};
const origin='https://intake.test';
function setup(){
  const records=new Map(),files=new Map();
  const state={records,files,order:null,captures:0,failSave:false,verifyStatus:200,wrongCapture:false,networkFails:false,failEnrichment:false,completionConflict:false,unsupportedFields:new Set()};
  const env={CLOUDKIT_CONTAINER:'test',CLOUDKIT_ENVIRONMENT:'development',CLOUDKIT_KEY_ID:'test',CLOUDKIT_PRIVATE_KEY:`-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`,PAYPAL_CLIENT_ID:'mock-client',PAYPAL_CLIENT_SECRET:'mock-secret',PAYPAL_WEBHOOK_ID:'mock-webhook',ATTACHMENT_SIGNING_SECRET:'mock-signing',ALLOWED_ORIGIN:origin,PETASSIST_OPERATOR_KEY:'c'.repeat(64),PAYPAL_ENVIRONMENT:'sandbox',ATTACHMENTS_BUCKET:{
    async put(name,stream,meta){files.set(name,{data:await new Response(stream).arrayBuffer(),meta});},
    async get(name){const file=files.get(name);return file?{body:file.data,customMetadata:file.meta.customMetadata,writeHttpMetadata(headers){headers.set('Content-Type',file.meta.httpMetadata.contentType);}}:null;},
    async delete(names){for(const name of Array.isArray(names)?names:[names])files.delete(name);}
  }};
  async function fetchMock(url,options={}){
    if(state.networkFails) throw new Error('Fixture upstream unavailable');
    const path=new URL(url).pathname;
    if(path.endsWith('/oauth2/token'))return Response.json({access_token:'mock-token'});
    if(path.endsWith('/verify-webhook-signature'))return Response.json({verification_status:'SUCCESS'},{status:state.verifyStatus});
    if(path.endsWith('/records/lookup')){const input=JSON.parse(options.body);return Response.json({records:input.records.map(r=>records.get(r.recordName)||{serverErrorCode:'UNKNOWN_ITEM'})});}
    if(path.endsWith('/records/modify')){
      if(state.failSave)return Response.json({records:[{serverErrorCode:'FAILED'}]});
      const input=JSON.parse(options.body),saved=[];
      if(state.failEnrichment && input.operations[0].operationType === "update")throw new Error("enrichment unavailable");
      if(state.completionConflict && input.operations[0].record.fields.paymentStatus?.value === "Paid"){state.completionConflict=false;const old=records.get(input.operations[0].record.recordName);records.set(old.recordName,{...old,recordChangeTag:String(Number(old.recordChangeTag)+1),fields:{...old.fields,paymentStatus:{value:"Refunded"}}});}
      const unsupported=input.operations.flatMap(op=>Object.keys(op.record.fields)).find(name=>state.unsupportedFields.has(name));
      if(unsupported)return Response.json({records:[{serverErrorCode:'BAD_REQUEST',reason:`Field '${unsupported}' is not defined for record type Question.`}]});
      for(const op of input.operations){const id=op.record.recordName||`question-${records.size+1}`;const previous=records.get(id);if(op.operationType === "update" && op.record.recordChangeTag !== previous?.recordChangeTag)return Response.json({records:[{serverErrorCode:"CONFLICT"}]});const record={recordName:id,recordChangeTag:String(Number(previous?.recordChangeTag||0)+1),recordType:'Question',fields:{...previous?.fields,...op.record.fields}};records.set(id,record);saved.push(record);}
      return Response.json({records:saved});
    }
    if(path==='/v2/checkout/orders'){state.order={...JSON.parse(options.body),id:'ORDER123',status:'APPROVED'};return Response.json(state.order);}
    if(path==='/v2/checkout/orders/ORDER123')return Response.json(state.order);
    if(path==='/v2/payments/captures/CAPTURE123')return Response.json({id:'CAPTURE123',supplementary_data:{related_ids:{order_id:'ORDER123'}}});
    if(path==='/v2/checkout/orders/ORDER123/capture'){
      state.captures++;
      state.order.status='COMPLETED';
      state.order.purchase_units[0].payments={captures:[{id:'CAPTURE123',status:'COMPLETED',amount:{value:state.wrongCapture?'0.01':state.order.purchase_units[0].amount.value,currency_code:'USD'}}]};
      return Response.json(state.order);
    }
    throw new Error('Unexpected fixture request '+path);
  }
  const context=vm.createContext({Request,Response,Headers,URL,TextEncoder,Uint8Array,File,crypto:webcrypto,fetch:fetchMock,btoa,atob,console});
  const worker=vm.runInContext(source+'\nworker;',context);
  const PaymentObject=vm.runInContext('PetAssistPayments',context);
  const objects=new Map();
  env.PETASSIST_PAYMENTS={idFromName:name=>name,get(name){
    if(!objects.has(name)){
      const entries=new Map();let chain=Promise.resolve();
      const storage={async get(key){return structuredClone(entries.get(key));},async put(key,value){entries.set(key,structuredClone(value));},async list(options){return new Map([...entries.entries()].filter(([key])=>key.startsWith(options.prefix||'') && (!options.startAfter || key>options.startAfter)).sort(([a],[b])=>a.localeCompare(b)).slice(0,options.limit||100));},transaction(action){const result=chain.then(()=>action(storage));chain=result.catch(()=>{});return result;}};
      const object=new PaymentObject({storage});objects.set(name,{fetch:(url,options)=>object.fetch(new Request(url,options))});
    }
    return objects.get(name);
  }};
  const call=(path,body,headers={})=>worker.fetch(new Request('https://checkout.test'+path,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json',...headers},body:JSON.stringify(body)}),env);
  return {state,env,worker,context,call};
}
async function paidSetup(){const s=setup();assert.equal((await s.call('/intake',fixture)).status,200);assert.equal((await s.call('/api/paypal/orders',{question:'question-1',amount:'0.01'})).status,200);return s;}

test('new menu persists server-priced, signed intake and a checkout link',async()=>{
  const s=setup();const r=await s.call('/intake',{...fixture,paymentAmount:'$1',paymentStatus:'Paid'});assert.equal(r.status,200);assert.match((await r.json()).checkoutURL,/\/pay\?question=question-1$/);
  const fields=s.state.records.get('question-1').fields;assert.equal(fields.paymentAmount.value,'$10');assert.equal(fields.paymentStatus.value,'Payment requested');assert.equal(fields.signedConsentName.value,fixture.signedConsentName);
});
test('all seven service variants have the intended price and channel',async()=>{
  const s=setup();const variants=[['Quick Question — Email · $10','$10','Email'],['Quick Question — Text · $10','$10','Text message'],['Detailed Guidance — Email · $15','$15','Email'],['Detailed Guidance — Text · $15','$15','Text message'],['Phone Support · $25','$25','Phone call'],['Free Community Support — Email','$0','Email'],['Free Community Support — Text','$0','Text message']];
  for(const [service,amount,reply] of variants){assert.equal((await s.call('/intake',{...fixture,requestedService:service})).status,200);const fields=[...s.state.records.values()].at(-1).fields;assert.equal(fields.paymentAmount.value,amount);assert.equal(fields.preferredReply.value,reply);}
});
test('Community Access bypasses payment regardless of supplied payment method',async()=>{const s=setup();const r=await s.call('/intake',{...fixture,requestedService:'Community Access — Email · $0',paymentMethod:'',phone:''});assert.equal(r.status,200);assert.equal((await r.json()).checkoutURL,'');assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'No payment required');});
test('rejects stale services, missing consent, unsigned consent, emergencies, and missing phone',async()=>{
  for(const patch of [{requestedService:'Quick email response · $15'},{acceptedTerms:'no'},{acceptedCommunicationPolicy:'no'},{signedConsentName:''},{signedConsentAt:'invalid'},{urination:'Not urinating'},{vomiting:'Repeated retching with little or nothing coming up'},{requestedService:'Phone Support · $25',phone:''}]){const s=setup();assert.equal((await s.call('/intake',{...fixture,...patch})).status,400);assert.equal(s.state.records.size,0);}
});
test('origin restrictions and rate limiting reject intake without saving',async()=>{const s=setup();assert.equal((await s.call('/intake',fixture,{Origin:'https://unrelated.test'})).status,403);s.env.INTAKE_RATE_LIMITER={async limit(){return {success:false};}};assert.equal((await s.call('/intake',fixture)).status,429);assert.equal(s.state.records.size,0);});
test('advertised four 10 MB files fit; over-limit and five-file fixtures fail',()=>{const s=setup();s.context.files=Array.from({length:4},()=>({name:'fixture',size:10*1024*1024}));assert.equal(vm.runInContext('validateFiles(files)',s.context),null);s.context.files[0].size++;assert.match(vm.runInContext('validateFiles(files)',s.context),/too large/);s.context.files=Array.from({length:5},()=>({name:'fixture',size:1}));assert.match(vm.runInContext('validateFiles(files)',s.context),/4 files/);});
test('private uploads are readable with a valid signature and fail on tampering or expiry',async()=>{
  const s=setup(),form=new FormData();for(const [k,v] of Object.entries(fixture))form.append(k,v);form.append('attachments',new File(['release fixture'],'fixture.txt',{type:'text/plain'}));
  const r=await s.worker.fetch(new Request('https://checkout.test/intake',{method:'POST',headers:{Origin:origin},body:form}),s.env);assert.equal(r.status,200);assert.equal(s.state.files.size,1);
  const summary=s.state.records.get('question-1').fields.attachmentSummary.value;const link=summary.slice(summary.indexOf('https://'));const get=await s.worker.fetch(new Request(link),s.env);assert.equal(get.status,200);assert.equal(await get.text(),'release fixture');assert.equal(get.headers.get('Cache-Control'),'private, no-store');
  const tampered=new URL(link);tampered.searchParams.set('signature','wrong');assert.equal((await s.worker.fetch(new Request(tampered),s.env)).status,401);tampered.searchParams.set('expires','1');assert.equal((await s.worker.fetch(new Request(tampered),s.env)).status,410);
});
test('failed CloudKit save removes newly uploaded orphan files',async()=>{const s=setup();s.state.failSave=true;const form=new FormData();for(const [k,v]of Object.entries(fixture))form.append(k,v);form.append('attachments',new File(['test'],'fixture.txt'));assert.equal((await s.worker.fetch(new Request('https://checkout.test/intake',{method:'POST',headers:{Origin:origin},body:form}),s.env)).status,502);assert.equal(s.state.files.size,0);});
test('order uses the server amount and bounded stable idempotency key',async()=>{const s=await paidSetup();assert.equal(s.state.order.purchase_units[0].amount.value,'10.00');assert.match(s.state.order.purchase_units[0].invoice_id,/^paws-/);});
test('capture recovers after CloudKit failure and repeated paid requests never capture twice',async()=>{const s=await paidSetup();s.state.failSave=true;const pending=await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});assert.equal(pending.status,202);assert.deepEqual(await pending.json(),{ok:true,status:'Paid',statusSyncPending:true});s.state.failSave=false;assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);assert.equal(s.state.captures,1);assert.equal((await s.call('/api/paypal/orders',{question:'question-1'})).status,409);});
test('capture rejects a different customer order and wrong captured amount',async()=>{let s=await paidSetup();s.state.order.purchase_units[0].custom_id='different-question';assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,409);assert.equal(s.state.captures,0);s=await paidSetup();s.state.wrongCapture=true;assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,502);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Payment requested');});
test('verified completion webhook repairs payment status; failures stay retryable',async()=>{
  const s=await paidSetup();s.state.failSave=true;await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1',method:'Apple Pay'});const event={event_type:'PAYMENT.CAPTURE.COMPLETED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}};
  assert.equal((await s.call('/paypal/webhook',event)).status,503);s.state.failSave=false;s.state.verifyStatus=500;assert.equal((await s.call('/paypal/webhook',event)).status,401);s.state.verifyStatus=200;assert.equal((await s.call('/paypal/webhook',event)).status,200);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Paid');
});
test('refund reconciliation reports storage failures and delayed completion does not resurrect a refund',async()=>{const s=await paidSetup();await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}};s.state.failSave=true;assert.equal((await s.call('/paypal/webhook',event)).status,503);s.state.failSave=false;assert.equal((await s.call('/paypal/webhook',event)).status,200);event.event_type='PAYMENT.CAPTURE.COMPLETED';assert.equal((await s.call('/paypal/webhook',event)).status,200);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Refunded');});
test('upstream exceptions return a clear 503 with matching CORS',async()=>{const s=setup();s.state.networkFails=true;const r=await s.call('/intake',fixture);assert.equal(r.status,503);assert.equal(r.headers.get('Access-Control-Allow-Origin'),origin);assert.ok(!(await r.text()).includes('mock-secret'));});
test('real refund resource shape resolves its capture and reconciles the order',async()=>{
  const s=await paidSetup();await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});
  s.state.order.purchase_units[0].payments.captures[0].status='REFUNDED';
  const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{id:'REFUND123',links:[{rel:'up',href:'https://api.sandbox.paypal.com/v2/payments/captures/CAPTURE123'}]}};
  assert.equal((await s.call('/paypal/webhook',event)).status,200);
  assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Refunded');
});
test('refund capture links cannot send credentials to another host or environment',async()=>{
  for(const href of ['https://attacker.invalid/v2/payments/captures/CAPTURE123','https://api.paypal.com/v2/payments/captures/CAPTURE123','https://api.sandbox.paypal.com/v2/payments/captures/CAPTURE123?redirect=1']){
    const s=await paidSetup();const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{links:[{rel:'up',href}]}};
    assert.equal((await s.call('/paypal/webhook',event)).status,502);
    assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Payment requested');
  }
});
test('older CloudKit schemas preserve missing fields and checkout status in a versioned envelope',async()=>{
  const s=setup();s.state.unsupportedFields=new Set(['breed','sex','paymentAmount','paymentStatus','paymentLink','signedConsentName']);
  const r=await s.call('/intake',{...fixture,breed:'Fictional mix'});assert.equal(r.status,200);assert.match((await r.json()).checkoutURL,/question-1/);
  const record=s.state.records.get('question-1');let packed=JSON.parse(record.fields.question.value);assert.equal(packed.question,fixture.question);assert.equal(packed.details.breed,'Fictional mix');assert.equal(packed.details.signedConsentName,fixture.signedConsentName);assert.equal(packed.details.paymentStatus,'Payment requested');assert.match(packed.details.paymentLink,/question-1/);
  assert.equal((await s.call('/api/paypal/orders',{question:'question-1'})).status,200);assert.equal(s.state.order.purchase_units[0].amount.value,'10.00');assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);
  packed=JSON.parse(record.fields.question.value);const updated=JSON.parse(s.state.records.get('question-1').fields.question.value);assert.equal(updated.details.paymentStatus,'Paid');assert.equal(updated.details.breed,'Fictional mix');assert.equal(updated.details.signedConsentName,fixture.signedConsentName);
  assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);assert.equal(s.state.captures,1);
});

test('a thrown CloudKit save cleans up uploads',async()=>{const s=setup();s.state.networkFails=true;const form=new FormData();for(const [k,v]of Object.entries(fixture))form.append(k,v);form.append('attachments',new File(['test'],'fixture.txt'));assert.equal((await s.worker.fetch(new Request('https://checkout.test/intake',{method:'POST',headers:{Origin:origin},body:form}),s.env)).status,503);assert.equal(s.state.files.size,0);});
test('committed intake remains successful when optional checkout enrichment throws',async()=>{const s=setup();s.state.failEnrichment=true;const r=await s.call('/intake',fixture);assert.equal(r.status,200);assert.match((await r.json()).checkoutURL,/question-1/);assert.equal(s.state.records.size,1);});
test('concurrent refund wins over completion using a conditional record update',async()=>{const s=await paidSetup();s.state.completionConflict=true;const r=await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});assert.equal(r.status,200);assert.equal((await r.json()).status,'Refunded');assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Refunded');assert.equal(s.state.captures,1);});
test('partial refund is recorded and cannot downgrade a full refund',async()=>{const s=await paidSetup();await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}};s.state.order.purchase_units[0].payments.captures[0].status='PARTIALLY_REFUNDED';assert.equal((await s.call('/paypal/webhook',event)).status,200);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Partially refunded');s.state.order.purchase_units[0].payments.captures[0].status='REFUNDED';await s.call('/paypal/webhook',event);s.state.order.purchase_units[0].payments.captures[0].status='PARTIALLY_REFUNDED';await s.call('/paypal/webhook',event);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Refunded');});

test('a failed second upload rolls back the complete batch before creating a question',async()=>{const s=setup();const put=s.env.ATTACHMENTS_BUCKET.put;let calls=0;s.env.ATTACHMENTS_BUCKET.put=async(...args)=>{await put(...args);if(++calls===2)throw new Error('upload interrupted');};const form=new FormData();for(const [k,v]of Object.entries(fixture))form.append(k,v);form.append('attachments',new File(['one'],'one.txt'));form.append('attachments',new File(['two'],'two.txt'));assert.equal((await s.worker.fetch(new Request('https://checkout.test/intake',{method:'POST',headers:{Origin:origin},body:form}),s.env)).status,503);assert.equal(s.state.files.size,0);assert.equal(s.state.records.size,0);});

test('cached free labels normalize without checkout; manual payment is rejected',async()=>{
  const s=setup();
  const free=await s.call('/intake',{...fixture,requestedService:'Community Access — Text · $0',paymentMethod:'Cash App'});
  assert.equal(free.status,200);assert.equal((await free.json()).checkoutURL,'');
  const fields=s.state.records.get('question-1').fields;
  assert.equal(fields.requestedService.value,'Free Community Support — Text');
  assert.equal(fields.paymentAmount.value,'$0');assert.equal(fields.paymentMethod.value,'Free Community Support');
  const count=s.state.records.size;
  assert.equal((await s.call('/intake',{...fixture,paymentMethod:'Cash App'})).status,400);
  assert.equal(s.state.records.size,count);
});

const petToken='a'.repeat(32);
test('PetAssist quotes enforce service prices, remain separate and survive repeat requests',async()=>{
  const s=setup();const body={token:petToken,service:'wellnessCheck',amount:'0.01',status:'Paid'};
  let r=await s.call('/petassist/bookings',body);assert.equal(r.status,200);let receipt=await r.json();assert.equal(receipt.amount,'$65');assert.equal(receipt.status,'Payment requested');assert.equal(s.state.records.size,0);
  assert.equal((await s.call('/petassist/bookings',body)).status,200);
  assert.equal((await s.call('/petassist/bookings',{...body,service:'nailTrim'})).status,409);
  assert.equal((await s.call('/petassist/bookings',{...body,service:'__proto__',token:'b'.repeat(32)})).status,400);
  assert.equal((await s.call('/petassist/bookings',body,{Origin:'https://attacker.invalid'})).status,403);
  r=await s.worker.fetch(new Request('https://checkout.test/petassist/bookings/'+petToken),s.env);assert.equal(r.status,200);assert.equal((await r.json()).amount,'$65');
  assert.equal((await s.worker.fetch(new Request('https://checkout.test/petassist/bookings/'+'c'.repeat(32)),s.env)).status,404);
});
test('PetAssist uses common capture and refund verification without resurrecting refunded payments',async()=>{
  const s=setup(),question='petassist-'+petToken;
  await s.call('/petassist/bookings',{token:petToken,service:'nailTrim'});
  assert.equal((await s.call('/api/paypal/orders',{question})).status,200);assert.match(s.state.order.purchase_units[0].invoice_id,/^petassist-/);
  assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question})).status,200);
  assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question})).status,200);assert.equal(s.state.captures,1);
  let r=await s.worker.fetch(new Request('https://checkout.test/petassist/bookings/'+petToken),s.env);assert.equal((await r.json()).status,'Paid');
  s.state.order.purchase_units[0].payments.captures[0].status='REFUNDED';
  const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{links:[{rel:'up',href:'https://api.sandbox.paypal.com/v2/payments/captures/CAPTURE123'}]}};
  assert.equal((await s.call('/paypal/webhook',event)).status,200);
  await s.call('/paypal/webhook',{event_type:'PAYMENT.CAPTURE.COMPLETED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}});
  r=await s.worker.fetch(new Request('https://checkout.test/petassist/bookings/'+petToken),s.env);assert.equal((await r.json()).status,'Refunded');
});

async function checkoutFixture(patch = {}) {
  const s = setup();
  await s.call('/intake', fixture);
  const response = await s.worker.fetch(new Request('https://checkout.test/pay?question=question-1'), s.env);
  const html = await response.text();
  const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)][0][1];
  const elements = Object.fromEntries(['status','applepay-status','applepay-container','applepay-button','paypal-buttons','checkout-controls','checkout-title','checkout-note','checkout-next'].map(id=>[id,{textContent:'',innerHTML:'',hidden:id==='checkout-next',focus(){this.focused=true;}}]));
  const calls = { sessions: [], orders: 0, captures: 0, confirmations: 0 };
  class AppleSession {
    static STATUS_SUCCESS = 1; static STATUS_FAILURE = 0;
    static canMakePayments() { return !patch.unsupported; }
    constructor(version, request) { if(patch.startFails) throw new Error('start'); this.request=request;calls.sessions.push(this); }
    begin() { this.begun = true; }
    abort() { this.aborted = true; }
    completeMerchantValidation(session) { this.merchantSession = session; }
    completePayment(status) { this.status = status; }
  }
  const applepay = {
    async config() { if(patch.configFails) throw new Error('config');return {isEligible:!patch.ineligible,countryCode:'US',merchantCapabilities:['supports3DS'],supportedNetworks:['visa']}; },
    async validateMerchant() { if(patch.validationFails) throw new Error('validation');return {merchantSession:{valid:true}}; },
    async confirmOrder(input) { calls.confirmations++;calls.confirmInput=input;if(patch.confirmFails) throw new Error('declined'); }
  };
  const paypal = { Applepay:()=>applepay, Buttons(options){calls.paypalOptions=options;return {render:async()=>{}};} };
  const context = vm.createContext({document:{getElementById:id=>elements[id]},window:{paypal,ApplePaySession:AppleSession},paypal,ApplePaySession:AppleSession,fetch:async(path,options)=>{
    if(path.endsWith('/capture')){calls.captures++;return Response.json({status:'Paid',statusSyncPending:!!patch.syncPending});}
    calls.orders++;return Response.json({id:'ORDER123'});
  }});
  vm.runInContext(script,context);
  await vm.runInContext('setupApplePay()',context);
  return {s,response,html,elements,calls};
}

test('checkout permits Apple Pay frames/images and PayPal provider subdomains',async()=>{
  const {response}=await checkoutFixture();const csp=response.headers.get('Content-Security-Policy');
  const directives=Object.fromEntries(csp.split(';').map(value=>{const [name,...sources]=value.trim().split(/\s+/);return [name,sources];}));
  assert.ok(directives['frame-src'].includes('https://applepay.cdn-apple.com'));
  assert.ok(directives['img-src'].includes('https://applepay.cdn-apple.com'));
  for(const name of ['script-src','frame-src','connect-src','img-src'])assert.ok(directives[name].includes('https://*.paypal.com'));
  assert.equal(directives['default-src'].join(' '),"'self'");
});
test('Apple Pay verification file is returned as a binary download without redirect',async()=>{
  const s=setup();const r=await s.worker.fetch(new Request('https://checkout.test/.well-known/apple-developer-merchantid-domain-association'),s.env);
  assert.equal(r.status,200);assert.equal(r.headers.get('Content-Type'),'application/octet-stream');assert.equal(await r.text(),'association');
});
test('Apple Pay validates merchant, requests billing address, confirms token and captures payment',async()=>{
  const {elements,calls}=await checkoutFixture({syncPending:true});elements['applepay-button'].onclick();elements['applepay-button'].onclick();
  assert.equal(calls.sessions.length,1);const session=calls.sessions[0];assert.equal(session.begun,true);
  assert.deepEqual(Array.from(session.request.requiredBillingContactFields),['postalAddress']);
  await session.onvalidatemerchant({validationURL:'https://apple-pay-gateway.apple.com/session'});assert.equal(session.merchantSession.valid,true);
  await session.onpaymentauthorized({payment:{token:{test:true},billingContact:{postalCode:'00000'}}});
  assert.equal(calls.orders,1);assert.equal(calls.confirmations,1);assert.equal(calls.captures,1);assert.equal(calls.confirmInput.orderId,'ORDER123');assert.equal(session.status,1);assert.match(elements.status.textContent,/Payment received.*updating/);
});
for(const [name,patch,expected]of [
  ['unavailable device',{unsupported:true},/unavailable in this browser/],
  ['ineligible merchant',{ineligible:true},/currently unavailable/],
  ['configuration failure',{configFails:true},/could not load/],
])test('Apple Pay explains '+name+' and preserves the PayPal checkout',async()=>{
  const {elements,calls}=await checkoutFixture(patch);assert.match(elements['applepay-status'].textContent,expected);assert.equal(calls.sessions.length,0);assert.ok(calls.paypalOptions.createOrder);
});
test('Apple Pay merchant validation failure explains the error and aborts before creating an order',async()=>{
  const {elements,calls}=await checkoutFixture({validationFails:true});elements['applepay-button'].onclick();const session=calls.sessions[0];await session.onvalidatemerchant({validationURL:'https://apple.test'});
  assert.equal(session.aborted,true);assert.equal(calls.orders,0);assert.match(elements['applepay-status'].textContent,/could not verify/);
});
test('Apple Pay declined confirmation never captures or reports success',async()=>{
  const {elements,calls}=await checkoutFixture({confirmFails:true});elements['applepay-button'].onclick();const session=calls.sessions[0];await session.onpaymentauthorized({payment:{token:{},billingContact:{}}});
  assert.equal(calls.captures,0);assert.equal(session.status,0);assert.match(elements['applepay-status'].textContent,/could not complete/);
});
test('Apple Pay start and cancellation errors leave checkout usable',async()=>{
  let f=await checkoutFixture({startFails:true});f.elements['applepay-button'].onclick();assert.match(f.elements['applepay-status'].textContent,/could not open/);
  f=await checkoutFixture();f.elements['applepay-button'].onclick();f.calls.sessions[0].oncancel();assert.match(f.elements['applepay-status'].textContent,/cancelled/);f.elements['applepay-button'].onclick();assert.equal(f.calls.sessions.length,2);
});
test('PayPal approval ends checkout and blocks another order',async()=>{
  const {elements,calls}=await checkoutFixture();assert.equal(await calls.paypalOptions.createOrder(),'ORDER123');await calls.paypalOptions.onApprove({orderID:'ORDER123'});assert.equal(calls.captures,1);assert.match(elements.status.textContent,/Payment received/);calls.paypalOptions.onCancel();assert.match(elements.status.textContent,/Payment received/);assert.equal(elements['checkout-controls'].hidden,true);assert.equal(elements['checkout-next'].hidden,false);assert.equal(elements['checkout-title'].textContent,'Payment received');assert.equal(elements.status.focused,true);await assert.rejects(calls.paypalOptions.createOrder(),/already paid/);assert.equal(calls.orders,1);
});


test('paid request revisits show confirmation and new question link without any payment SDK',async()=>{
  const s=await paidSetup();await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});
  const r=await s.worker.fetch(new Request('https://checkout.test/pay?question=question-1'),s.env);const html=await r.text();assert.equal(r.status,200);assert.match(html,/This request is already paid/);assert.match(html,/Ask another question/);assert.match(html,/https:\/\/paws-whiskers-care-line.dkjmmz6whh.workers.dev\/#askSection/);assert.doesNotMatch(html,/paypal-buttons|applepay-button|<script/);assert.equal((await s.call('/api/paypal/orders',{question:'question-1'})).status,409);
});
test('Apple Pay completion removes payment choices and cannot open a second session',async()=>{
  const {elements,calls}=await checkoutFixture();const click=elements['applepay-button'].onclick;click();await calls.sessions[0].onpaymentauthorized({payment:{token:{},billingContact:{}}});assert.equal(elements['checkout-controls'].hidden,true);assert.equal(elements['paypal-buttons'].innerHTML,'');assert.equal(elements['applepay-container'].innerHTML,'');assert.equal(elements['checkout-next'].hidden,false);click();assert.equal(calls.sessions.length,1);assert.match(elements['checkout-note'].textContent,/Your question and payment have been received/);
});

test('PayPal cancellation before payment preserves checkout choices',async()=>{const {elements,calls}=await checkoutFixture();calls.paypalOptions.onCancel();assert.match(elements.status.textContent,/cancelled/);assert.equal(elements['checkout-controls'].hidden,false);assert.equal(elements['checkout-next'].hidden,true);});

test('historical unpaid requests retain their original price after the increase',async()=>{
  for(const amount of [5,10,20,30,35]){
    const s=setup();await s.call('/intake',fixture);s.state.records.get('question-1').fields.paymentAmount={value:'$'+amount};
    const r=await s.call('/api/paypal/orders',{question:'question-1'});assert.equal(r.status,200);assert.equal(s.state.order.purchase_units[0].amount.value,amount.toFixed(2));
  }
});
test('cached old paid menus are rejected before saving a new request',async()=>{
  for(const service of ['Quick Question — Email · $5','Detailed Guidance — Text · $10','Phone Support · $20']){
    const s=setup();assert.equal((await s.call('/intake',{...fixture,requestedService:service})).status,400);assert.equal(s.state.records.size,0);
  }
});
test('frontend service labels match the updated checkout prices',async()=>{
  const s=setup();assert.equal(vm.runInContext('amountFromService("Quick Question — Email · $10")',s.context),'$10');
  const html=await readFile(new URL('../../index.html',import.meta.url),'utf8');
  const fn=html.match(/function amountFromService\(service\) \{[\s\S]*?\n  \}/)[0];
  assert.equal(vm.runInNewContext(fn+'\namountFromService("Quick Question — Email · $10")',{isFreeSupport:()=>false}),'$10');
  for(const label of ['Quick Question — Email · $10','Detailed Guidance — Email · $15','Phone Support · $25'])assert.ok(html.includes('value="'+label+'"'));
});


const visitFixture={token:"d".repeat(32),clientAccess:"e".repeat(64),service:"nailTrim",clientName:"Test client",email:"visit@example.invalid",phone:"",petName:"Test pet",species:"Dog",address:"Test address",notes:"Website request",preferredAt:new Date(Date.now()+86400000).toISOString(),acceptedPrivacy:true};
const operatorHeaders={Authorization:"Bearer "+"c".repeat(64)};
async function visitGet(s,path,headers={}){return s.worker.fetch(new Request("https://checkout.test"+path,{headers}),s.env);}
async function visitPatch(s,token,input,headers=operatorHeaders){return s.worker.fetch(new Request("https://checkout.test/petassist/operator/visits/"+token,{method:"PATCH",headers:{...headers,"Content-Type":"application/json"},body:JSON.stringify(input)}),s.env);}
test("website visits enter a protected inbox without exposing client details in checkout",async()=>{
 const s=setup();const result=await s.call("/petassist/requests",visitFixture);assert.equal(result.status,200);
 assert.equal((await s.call("/petassist/requests",visitFixture)).status,200);
 assert.equal((await visitGet(s,"/petassist/operator/visits")).status,401);
 assert.equal((await visitGet(s,"/petassist/operator/visits",{Authorization:"Bearer wrong"})).status,401);
 let page=await (await visitGet(s,"/petassist/operator/visits",operatorHeaders)).json();assert.equal(page.visits.length,1);assert.equal(page.visits[0].clientName,"Test client");
 const publicReceipt=await (await visitGet(s,"/petassist/bookings/"+visitFixture.token)).json();assert.ok(!JSON.stringify(publicReceipt).includes("visit@example.invalid"));assert.ok(!JSON.stringify(publicReceipt).includes("Test address"));
 assert.equal((await s.call("/api/paypal/orders",{question:"petassist-"+visitFixture.token})).status,400);
 const refused=await visitPatch(s,visitFixture.token,{status:"accepted",expectedVersion:page.visits[0].version});assert.equal(refused.status,400);
 const accepted=await visitPatch(s,visitFixture.token,{status:"accepted",scheduledAt:visitFixture.preferredAt,expectedVersion:page.visits[0].version});assert.equal(accepted.status,200);
 assert.equal((await s.call("/api/paypal/orders",{question:"petassist-"+visitFixture.token})).status,200);assert.equal(s.state.order.purchase_units[0].amount.value,"35.00");
 assert.equal((await visitPatch(s,visitFixture.token,{status:"cancelled",expectedVersion:"1"})).status,409);
 page=await (await visitGet(s,"/petassist/operator/visits",operatorHeaders)).json();
 assert.equal((await visitPatch(s,visitFixture.token,{status:"cancelled",expectedVersion:page.visits[0].version})).status,200);
 assert.equal((await s.call("/api/paypal/orders",{question:"petassist-"+visitFixture.token})).status,400);
 assert.equal((await s.call("/api/paypal/orders/ORDER123/capture",{question:"petassist-"+visitFixture.token})).status,409);assert.equal(s.state.captures,0);
 assert.match(await (await visitGet(s,"/petassist/pay?token="+visitFixture.token)).text(),/Visit cancelled/);
});
test("client conversation needs its separate access key and preserves the business identity",async()=>{
 const s=setup();await s.call("/petassist/requests",visitFixture);const path="/petassist/client/visits/"+visitFixture.token;
 assert.equal((await visitGet(s,path)).status,401);assert.equal((await visitGet(s,path,{Authorization:"Bearer "+visitFixture.token})).status,401);
 const clientHeaders={Authorization:"Bearer "+visitFixture.clientAccess};
 assert.equal((await s.call(path+"/messages",{text:"Can we confirm the time?",sender:"business"},clientHeaders)).status,200);
 assert.equal((await s.call("/petassist/operator/visits/"+visitFixture.token+"/messages",{text:"Confirmed through our business.",sender:"client"},operatorHeaders)).status,200);
 const visit=await (await visitGet(s,path,clientHeaders)).json();assert.equal(visit.messages.length,2);assert.equal(visit.messages[0].sender,"client");assert.equal(visit.messages[1].sender,"business");assert.ok(!("email" in visit));assert.ok(!("clientLink" in visit));
 const other={...visitFixture,token:"f".repeat(32),clientAccess:"a".repeat(64)};await s.call("/petassist/requests",other);
 assert.equal((await visitGet(s,"/petassist/client/visits/"+other.token,clientHeaders)).status,401);
 assert.equal((await s.call(path+"/messages",{text:" "},clientHeaders)).status,400);
});
test("visit form rejects invalid contact, dates, origin and consent before storage",async()=>{
 for(const patch of [{email:"bad"},{clientName:""},{petName:""},{address:""},{preferredAt:"invalid"},{preferredAt:"2020-01-01"},{acceptedPrivacy:false},{service:"__proto__"},{clientAccess:"short"}]){
  const s=setup();assert.equal((await s.call("/petassist/requests",{...visitFixture,...patch})).status,400);
  assert.equal((await (await visitGet(s,"/petassist/operator/visits",operatorHeaders)).json()).visits.length,0);
 }
 const s=setup();assert.equal((await s.call("/petassist/requests",visitFixture,{Origin:"https://wrong.test"})).status,403);
});
test("appointment progress is separate from payment and invalid transitions do not alter history",async()=>{
 const s=setup();await s.call("/petassist/requests",visitFixture);let v=(await (await visitGet(s,"/petassist/operator/visits",operatorHeaders)).json()).visits[0];
 assert.equal((await visitPatch(s,v.token,{status:"completed",expectedVersion:v.version})).status,409);
 for(const status of ["accepted","en-route","in-progress","completed"]){const r=await visitPatch(s,v.token,{status,expectedVersion:v.version,...(status==="accepted"?{scheduledAt:visitFixture.preferredAt}:{})});assert.equal(r.status,200);v=await r.json();assert.equal(v.status,"Payment requested");}
 assert.equal((await visitPatch(s,v.token,{status:"accepted",expectedVersion:v.version})).status,409);
});

test("removing client details revokes access and checkout while retaining verified payment history",async()=>{
 const s=setup(); await s.call("/petassist/requests",visitFixture);
 const record=await (await visitGet(s,"/petassist/operator/visits/"+visitFixture.token,operatorHeaders)).json();
 const remove=(headers,version)=>s.worker.fetch(new Request("https://checkout.test/petassist/operator/visits/"+visitFixture.token,{method:"DELETE",headers:{...headers,"Content-Type":"application/json"},body:JSON.stringify({expectedVersion:version})}),s.env);
 assert.equal((await remove({},record.version)).status,401);
 assert.equal((await remove(operatorHeaders,"stale")).status,409);
 assert.equal((await remove(operatorHeaders,record.version)).status,200);
 assert.equal((await visitGet(s,"/petassist/client/visits/"+visitFixture.token,{Authorization:"Bearer "+visitFixture.clientAccess})).status,404);
 assert.equal((await (await visitGet(s,"/petassist/operator/visits",operatorHeaders)).json()).visits.length,0);
 assert.equal((await s.call("/api/paypal/orders",{question:"petassist-"+visitFixture.token})).status,400);
 assert.equal((await visitGet(s,"/petassist/bookings/"+visitFixture.token)).status,200);
});
test("private visit browser preflight permits bearer authorization",async()=>{
 const s=setup();const response=await s.worker.fetch(new Request("https://checkout.test/petassist/client/visits/"+visitFixture.token,{method:"OPTIONS",headers:{Origin:origin,"Access-Control-Request-Headers":"authorization"}}),s.env);
 assert.equal(response.status,204);assert.match(response.headers.get("Access-Control-Allow-Headers"),/Authorization/);
});
