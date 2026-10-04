import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';

const source = (await readFile(new URL('../cloudkit-worker.js', import.meta.url),'utf8')).replace(/^import .*;$/m,'const applePayDomainAssociation = "association";').replace('export default {','const worker = {');
const key=await webcrypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const pem=Buffer.from(await webcrypto.subtle.exportKey('pkcs8',key.privateKey)).toString('base64');
const fixture={name:'Release test',email:'release@example.invalid',phone:'5555555555',species:'Dog',sex:'Unknown',reproductiveStatus:'Unknown',category:'Other',symptomOnset:'General question',symptomTrend:'Not applicable / general question',appetite:'Normal',drinking:'Normal',urination:'Normal',stool:'Normal',energy:'Normal',vomiting:'None',question:'How can I provide enrichment?',requestedService:'Quick Question — Email · $5',paymentMethod:'PayPal or Apple Pay',signedConsentName:'Release test',signedConsentAt:'2026-10-04T16:00:00Z',acceptedTerms:'yes',acceptedCommunicationPolicy:'yes'};
const origin='https://intake.test';
function setup(){
  const records=new Map(),files=new Map();
  const state={records,files,order:null,captures:0,failSave:false,verifyStatus:200,wrongCapture:false,networkFails:false,failEnrichment:false,completionConflict:false,unsupportedFields:new Set()};
  const env={CLOUDKIT_CONTAINER:'test',CLOUDKIT_ENVIRONMENT:'development',CLOUDKIT_KEY_ID:'test',CLOUDKIT_PRIVATE_KEY:`-----BEGIN PRIVATE KEY-----\n${pem}\n-----END PRIVATE KEY-----`,PAYPAL_CLIENT_ID:'mock-client',PAYPAL_CLIENT_SECRET:'mock-secret',PAYPAL_WEBHOOK_ID:'mock-webhook',ATTACHMENT_SIGNING_SECRET:'mock-signing',ALLOWED_ORIGIN:origin,PAYPAL_ENVIRONMENT:'sandbox',ATTACHMENTS_BUCKET:{
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
  const call=(path,body,headers={})=>worker.fetch(new Request('https://checkout.test'+path,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json',...headers},body:JSON.stringify(body)}),env);
  return {state,env,worker,context,call};
}
async function paidSetup(){const s=setup();assert.equal((await s.call('/intake',fixture)).status,200);assert.equal((await s.call('/api/paypal/orders',{question:'question-1',amount:'0.01'})).status,200);return s;}

test('new menu persists server-priced, signed intake and a checkout link',async()=>{
  const s=setup();const r=await s.call('/intake',{...fixture,paymentAmount:'$1',paymentStatus:'Paid'});assert.equal(r.status,200);assert.match((await r.json()).checkoutURL,/\/pay\?question=question-1$/);
  const fields=s.state.records.get('question-1').fields;assert.equal(fields.paymentAmount.value,'$5');assert.equal(fields.paymentStatus.value,'Payment requested');assert.equal(fields.signedConsentName.value,fixture.signedConsentName);
});
test('all seven service variants have the intended price and channel',async()=>{
  const s=setup();const variants=[['Quick Question — Email · $5','$5','Email'],['Quick Question — Text · $5','$5','Text message'],['Detailed Guidance — Email · $10','$10','Email'],['Detailed Guidance — Text · $10','$10','Text message'],['Phone Support · $20','$20','Phone call'],['Free Community Support — Email','$0','Email'],['Free Community Support — Text','$0','Text message']];
  for(const [service,amount,reply] of variants){assert.equal((await s.call('/intake',{...fixture,requestedService:service})).status,200);const fields=[...s.state.records.values()].at(-1).fields;assert.equal(fields.paymentAmount.value,amount);assert.equal(fields.preferredReply.value,reply);}
});
test('Community Access bypasses payment regardless of supplied payment method',async()=>{const s=setup();const r=await s.call('/intake',{...fixture,requestedService:'Community Access — Email · $0',paymentMethod:'',phone:''});assert.equal(r.status,200);assert.equal((await r.json()).checkoutURL,'');assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'No payment required');});
test('rejects stale services, missing consent, unsigned consent, emergencies, and missing phone',async()=>{
  for(const patch of [{requestedService:'Quick email response · $10'},{acceptedTerms:'no'},{acceptedCommunicationPolicy:'no'},{signedConsentName:''},{signedConsentAt:'invalid'},{urination:'Not urinating'},{vomiting:'Repeated retching with little or nothing coming up'},{requestedService:'Phone Support · $20',phone:''}]){const s=setup();assert.equal((await s.call('/intake',{...fixture,...patch})).status,400);assert.equal(s.state.records.size,0);}
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
test('order uses the server amount and bounded stable idempotency key',async()=>{const s=await paidSetup();assert.equal(s.state.order.purchase_units[0].amount.value,'5.00');assert.match(s.state.order.purchase_units[0].invoice_id,/^paws-/);});
test('capture recovers after CloudKit failure and repeated paid requests never capture twice',async()=>{const s=await paidSetup();s.state.failSave=true;assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,502);s.state.failSave=false;assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);assert.equal(s.state.captures,1);assert.equal((await s.call('/api/paypal/orders',{question:'question-1'})).status,409);});
test('capture rejects a different customer order and wrong captured amount',async()=>{let s=await paidSetup();s.state.order.purchase_units[0].custom_id='different-question';assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,409);assert.equal(s.state.captures,0);s=await paidSetup();s.state.wrongCapture=true;assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,502);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Payment requested');});
test('verified completion webhook repairs payment status; failures stay retryable',async()=>{
  const s=await paidSetup();s.state.failSave=true;await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1',method:'Apple Pay'});const event={event_type:'PAYMENT.CAPTURE.COMPLETED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}};
  assert.equal((await s.call('/paypal/webhook',event)).status,503);s.state.failSave=false;s.state.verifyStatus=500;assert.equal((await s.call('/paypal/webhook',event)).status,401);s.state.verifyStatus=200;assert.equal((await s.call('/paypal/webhook',event)).status,200);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Paid');
});
test('refund reconciliation reports storage failures and delayed completion does not resurrect a refund',async()=>{const s=await paidSetup();await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'});const event={event_type:'PAYMENT.CAPTURE.REFUNDED',resource:{supplementary_data:{related_ids:{order_id:'ORDER123'}}}};s.state.failSave=true;assert.equal((await s.call('/paypal/webhook',event)).status,503);s.state.failSave=false;assert.equal((await s.call('/paypal/webhook',event)).status,200);event.event_type='PAYMENT.CAPTURE.COMPLETED';assert.equal((await s.call('/paypal/webhook',event)).status,200);assert.equal(s.state.records.get('question-1').fields.paymentStatus.value,'Refunded');});
test('upstream exceptions return a clear 503 with matching CORS',async()=>{const s=setup();s.state.networkFails=true;const r=await s.call('/intake',fixture);assert.equal(r.status,503);assert.equal(r.headers.get('Access-Control-Allow-Origin'),origin);assert.ok(!(await r.text()).includes('mock-secret'));});
test('older CloudKit schemas preserve missing fields and checkout status in a versioned envelope',async()=>{
  const s=setup();s.state.unsupportedFields=new Set(['breed','sex','paymentAmount','paymentStatus','paymentLink','signedConsentName']);
  const r=await s.call('/intake',{...fixture,breed:'Fictional mix'});assert.equal(r.status,200);assert.match((await r.json()).checkoutURL,/question-1/);
  const record=s.state.records.get('question-1');let packed=JSON.parse(record.fields.question.value);assert.equal(packed.question,fixture.question);assert.equal(packed.details.breed,'Fictional mix');assert.equal(packed.details.signedConsentName,fixture.signedConsentName);assert.equal(packed.details.paymentStatus,'Payment requested');assert.match(packed.details.paymentLink,/question-1/);
  assert.equal((await s.call('/api/paypal/orders',{question:'question-1'})).status,200);assert.equal(s.state.order.purchase_units[0].amount.value,'5.00');assert.equal((await s.call('/api/paypal/orders/ORDER123/capture',{question:'question-1'})).status,200);
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
