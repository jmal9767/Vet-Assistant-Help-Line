#!/usr/bin/env python3
"""Generate static, offline-readable web and Swift copy from service-menu.json.

Run with --check in CI to catch price, benefit and timeframe drift.
No server, JavaScript or Xcode resource setup is needed to display prices.
"""
import argparse
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MENU = json.loads((ROOT / "service-menu.json").read_text())


def html_menu(compact=False):
    esc = html.escape
    parts = ['<p class="service-intro">One-time prices in USD. One pet, one nonmedical care topic. No subscription.</p>', '<div class="service-grid">']
    for s in MENU["services"]:
        parts.append(f'''<article class="service-option" data-service-id="{s['id']}">
  <div class="service-top"><h3>{esc(s['name'])}</h3><span class="service-amount">${s['amount']}</span></div>
  <p class="service-delivery">{esc(s['delivery'])}</p>
  <p>{esc(s['detail'])}</p>
  <p class="service-timing">{esc(s['timing'])}</p>
</article>''')
    parts += ['</div>', f'<p class="service-included">{esc(MENU["included"])}</p>']
    if compact:
        parts.append('<p class="service-summary">Exact deadline or appointment confirmed before payment. Business days: Mon–Fri, excluding U.S. federal holidays, Pacific Time. Session recap: within 1 business day; clarification reply: within 2 business days. Allow up to 2 business days for your initial quote. No charge to submit. Full refund if you do not feel your question was answered. Scan for full terms.</p>')
    else:
        parts.append(f'<p>{esc(MENU["requestTiming"])}</p>')
        for heading, keys in [("When will I hear back?", ["timing", "booking"]), ("How does the included clarification work?", ["followUp"]), ("Price confirmation and refunds", ["guarantee"])]:
            parts.append(f'<details class="service-policy"><summary>{heading}</summary>')
            parts.extend(f'<p>{esc(MENU[k])}</p>' for k in keys)
            parts.append('</details>')
    return '\n'.join(parts)


def swift_copy():
    def q(value):
        return json.dumps(value, ensure_ascii=False)
    result = [f'    static let {key} = {q(MENU[key])}' for key in ["headline", "purpose", "scope", "included", "timing", "booking", "followUp", "guarantee", "requestTiming"]]
    for source, target in [("howItWorks", "howItWorks"), ("examples", "canHelpWith")]:
        result.append(f'    static let {target} = [\n' + ',\n'.join('        ' + q(v) for v in MENU[source]) + '\n    ]')
    result.append('    static let priceMenu: [PriceSection] = [')
    for group in dict.fromkeys(s['group'] for s in MENU['services']):
        result.append(f'        PriceSection(title: {q(group)}, items: [')
        for s in MENU['services']:
            if s['group'] == group:
                detail = s['delivery'] + '. ' + s['detail'] + ' ' + s['timing'] + '.'
                result.append(f'            ServicePrice(service: {q(s["name"])}, price: "${s["amount"]}", detail: {q(detail)}),')
        result.append('        ]),')
    result.append('    ]')
    return '\n'.join(result)


def replace_block(content, name, replacement, swift=False):
    start = f'// BEGIN {name}' if swift else f'<!-- BEGIN {name} -->'
    end = f'// END {name}' if swift else f'<!-- END {name} -->'
    assert content.count(start) == content.count(end) == 1, f'Missing or duplicate {name} markers'
    before, rest = content.split(start)
    _, after = rest.split(end)
    return before + start + '\n' + replacement + '\n' + end + after


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outdated = []
    for name in ['index.html', 'welcome.html', 'poster.html', 'VetAssistantHelpLine/HelplineConfig.swift']:
        path = ROOT / name
        old = path.read_text()
        swift = name.endswith('.swift')
        new = replace_block(old, 'SERVICE MENU', swift_copy() if swift else html_menu(name == 'poster.html'), swift)
        if name == 'index.html':
            options = ['<option value="">Choose an option…</option>']
            for s in MENU['services']:
                options.append(f'<option value="{s["id"]}" data-channel="{s["channel"]}">{html.escape(s["name"])} — ${s["amount"]}</option>')
            new = replace_block(new, 'SERVICE OPTIONS', '\n'.join(options))
        if old != new:
            if args.check:
                outdated.append(name)
            else:
                path.write_text(new)
    if outdated:
        raise SystemExit('Run python3 scripts/sync_service_menu.py: ' + ', '.join(outdated))
    print('Service menu is synchronized.' if args.check else 'Service menu generated.')


if __name__ == '__main__':
    main()
