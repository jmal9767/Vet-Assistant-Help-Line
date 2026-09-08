const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const source = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');
const serviceHTML = html.match(/<select id="service"[\s\S]*?<\/select>/)[0];
const options = [...serviceHTML.matchAll(/<option value="([^"]*)"(?: data-channel="([^"]*)")?>([^<]*)<\/option>/g)]
  .map(m => ({ value: m[1], dataset: { channel: m[2] }, textContent: m[3] }));

function setup(worker = false) {
  const elements = {};
  for (const id of ['intakeForm','service','delivery','phone','deliveryRow','phoneRequirement','name','email','species','age','category','question','website','askSection']) {
    elements[id] = { value: '', textContent: '', innerHTML: '', hidden: false, required: false, listeners: {},
      addEventListener(event, fn) { this.listeners[event] = fn; } };
  }
  Object.assign(elements.service, { options, selectedIndex: 0 });
  elements.delivery.value = 'email';
  Object.assign(elements.name, { value: 'Test Client' });
  elements.email.value = 'client@example.test';
  elements.species.value = 'Dog';
  elements.category.value = 'New pet questions';
  elements.question.value = 'Help me organize a new-pet routine.';
  const button = { textContent: 'Send my question', disabled: false };
  const form = elements.intakeForm;
  form.reportValidity = () => Boolean(elements.service.value) && (!elements.phone.required || Boolean(elements.phone.value));
  form.querySelector = () => button;
  form.appendChild = element => { elements[element.id] = element; };
  const requests = [];
  const alerts = [];
  const context = vm.createContext({
    document: { getElementById: id => elements[id] || null, createElement: () => ({}) },
    window: { location: { href: '', protocol: 'http:' }, addEventListener() {} },
    navigator: {}, alert: text => alerts.push(text),
    fetch: async (url, init) => { requests.push({ url, payload: JSON.parse(init.body) }); return { ok: true }; }
  });
  vm.runInContext(source, context);
  if (worker) vm.runInContext('WORKER_URL = "https://worker.example.test"', context);
  const choose = id => {
    elements.service.selectedIndex = options.findIndex(o => o.value === id);
    elements.service.value = id;
    elements.service.listeners.change();
  };
  const submit = async () => { form.listeners.submit({ preventDefault() {}, target: form }); await new Promise(setImmediate); };
  return { elements, context, requests, alerts, choose, submit };
}

test('all four selectable services have a distinct ID and published price', () => {
  const labels = options.slice(1).map(o => o.textContent);
  assert.deepEqual(labels, ['Focused written answer — $10','Detailed written guide — $20','Live text session — $25','Phone support session — $35']);
  assert.equal(new Set(options.slice(1).map(o => o.value)).size, 4);
});

test('email delivery stays email when an optional phone number is supplied', async () => {
  const s = setup(); s.choose('written-answer'); s.elements.phone.value = '+15555550100';
  await s.submit();
  const body = new URL(s.context.window.location.href).searchParams.get('body');
  assert.match(body, /Requested service: Focused written answer — \$10\nDelivery: email/);
  assert.match(body, /Contact phone: \+15555550100/);
  assert.doesNotMatch(body, /text reply requested/);
  assert.match(s.elements.mailtoNote.innerHTML, /press send there/);
});

test('focused text requires a phone and preserves the same $10 price', async () => {
  const s = setup(true); s.choose('written-answer');
  s.elements.delivery.value = 'text'; s.elements.delivery.listeners.change();
  assert.equal(s.elements.phone.required, true);
  await s.submit(); assert.equal(s.requests.length, 0);
  s.elements.phone.value = '+15555550100'; await s.submit();
  assert.match(s.requests[0].payload.question, /Focused written answer — \$10\nDelivery: text/);
});

for (const [id, label, channel] of [['text-session','Live text session — $25','text'],['phone-session','Phone support session — $35','phone']]) {
  test(`${id} requires contact number and survives the CloudKit request payload`, async () => {
    const s = setup(true); s.choose(id);
    assert.equal(s.elements.phone.required, true);
    assert.equal(s.elements.deliveryRow.hidden, true);
    await s.submit(); assert.equal(s.requests.length, 0);
    s.elements.phone.value = '+15555550100'; await s.submit();
    assert.ok(s.requests[0].payload.question.startsWith(`Requested service: ${label}\nDelivery: ${channel}\n\n`));
    assert.match(s.elements.askSection.innerHTML, /No payment has been taken/);
    assert.match(s.elements.askSection.innerHTML, /confirmed before payment/);
  });
}

test('switching to a detailed guide clears a previous text-delivery requirement', async () => {
  const s = setup(true); s.choose('written-answer'); s.elements.delivery.value = 'text'; s.elements.delivery.listeners.change();
  s.choose('written-guide'); assert.equal(s.elements.phone.required, false);
  await s.submit(); assert.match(s.requests[0].payload.question, /Detailed written guide — \$20\nDelivery: email/);
});

test('a request without a service never reaches the relay', async () => {
  const s = setup(true); await s.submit(); assert.equal(s.requests.length, 0);
});

test('honeypot submissions remain blocked', async () => {
  const s = setup(true); s.choose('written-guide'); s.elements.website.value = 'spam';
  await s.submit(); assert.equal(s.requests.length, 0);
});
