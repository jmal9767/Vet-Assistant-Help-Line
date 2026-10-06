import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../../conversation.js', import.meta.url), 'utf8');
function page() {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id, { textContent: '', hidden: false, children: [],
      addEventListener() {}, replaceChildren() { this.children = []; }, append(...items) { this.children.push(...items); } });
    return elements.get(id);
  };
  const context = vm.createContext({ URL, location: { hash: '' }, document: {
    hidden: true, getElementById: element, createElement: () => ({ append() {} }), addEventListener() {},
  }, window: { addEventListener() {} } });
  vm.runInContext(source, context);
  const render = paymentStatus => context.render({ service: 'Quick Question', question: 'Enrichment ideas', paymentStatus,
    checkoutURL: 'https://vet-helpline-development.dkjmmz6whh.workers.dev/pay?question=example', messages: [] });
  return { element, render };
}

test('private conversation hides payment until approval, then updates without reloading', () => {
  const p = page();
  p.render('Awaiting approval');
  assert.equal(p.element('pay').hidden, true);
  assert.match(p.element('availability').textContent, /not been charged/);
  p.render('Payment requested');
  assert.equal(p.element('pay').hidden, false);
  p.render('Paid');
  assert.equal(p.element('pay').hidden, true);
});
test('declined and free conversations never expose a payment button even with a stale URL', () => {
  const p = page();
  p.render('Declined — no charge');
  assert.equal(p.element('pay').hidden, true);
  assert.match(p.element('availability').textContent, /declined without payment/);
  p.render('No payment required');
  assert.equal(p.element('pay').hidden, true);
  assert.match(p.element('availability').textContent, /no payment is needed/);
});
