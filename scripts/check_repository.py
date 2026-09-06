"""Cross-surface gates: asset links, UI IDs, catalog, no obsolete purchase flow."""
import json
import plistlib
import re
import subprocess
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]


class Page(HTMLParser):
    def __init__(self, name):
        super().__init__(); self.name=name; self.ids=set(); self.links=[]
        self.feed((ROOT/name).read_text())
    def handle_starttag(self, tag, attrs):
        values=dict(attrs)
        if "id" in values:
            assert values["id"] not in self.ids, (self.name,"duplicate ID",values["id"])
            self.ids.add(values["id"])
        for attribute in ("href","src"):
            if values.get(attribute): self.links.append(values[attribute])
        assert not any(key.startswith("on") for key in values), (self.name,"inline JS blocked by CSP")


def main():
    pages={name:Page(name) for name in ("index.html","status.html","terms.html","privacy.html")}
    for name,page in pages.items():
        for link in page.links:
            url=urlsplit(link)
            if url.scheme or url.netloc: continue
            path=url.path or name
            assert path=="brand.png" or (ROOT/path).is_file(), (name,"missing link",link)
            if url.fragment and path in pages:
                assert url.fragment in pages[path].ids, (name,"missing anchor",link)
    for script,page in (("intake.js","index.html"),("status.js","status.html")):
        code=(ROOT/script).read_text()
        for identifier in re.findall(r'(?:byId|\$)\("([\w-]+)"\)',code):
            assert identifier in pages[page].ids, (script,"missing element",identifier)
        assert ".innerHTML" not in code
        assert "credentials:\"omit\"" in code or 'credentials: "omit"' in code
    catalog=json.loads((ROOT/"VetAssistantHelpLine/Resources/service-catalog.json").read_text())
    assert catalog["priceCents"]==999 and len(catalog["categories"])==5
    assert "$9.99" in (ROOT/"terms.html").read_text()
    assert len({c["id"] for c in catalog["categories"]})==5
    for file in (ROOT/"VetAssistantHelpLine").rglob("*.swift"):
        content=file.read_text()
        assert "import StoreKit" not in content, file
        assert "UserDefaults" not in content, file
        assert "sk_live_" not in content and "sk_test_" not in content, file
    assert not (ROOT/"operator").exists() or not list((ROOT/"operator").glob("*.py"))
    project=(ROOT/"VetAssistantHelpLine.xcodeproj/project.pbxproj").read_text()
    assert "InAppPurchase" not in project and ".storekit" not in project
    assert project.count("NSFaceIDUsageDescription")==2
    ElementTree.parse(ROOT/"VetAssistantHelpLine.xcodeproj/xcshareddata/xcschemes/VetAssistantHelpLine.xcscheme")
    manifest=plistlib.loads((ROOT/"VetAssistantHelpLine/PrivacyInfo.xcprivacy").read_bytes())
    assert not manifest["NSPrivacyTracking"]
    assert not manifest["NSPrivacyAccessedAPITypes"]
    owner_client=(ROOT/"VetAssistantHelpLine/Services/PrivateInbox.swift").read_text()
    assert 'request("api/admin/catalog")' in owner_client
    assert '"api/catalog"' not in owner_client
    public_text="\n".join((ROOT/name).read_text() for name in pages)
    for internal in ("answerChecklist","answerGoal","Keychain","private device key","iPhone app is private","Private service note"):
        assert internal not in public_text, ("internal content in client page",internal)
    for doc in ("README.md","SECURITY.md","docs/SOLO_WORKFLOW.md","docs/RESPONSE_TEMPLATES.md","docs/LEGAL_SCOPE.md","docs/PRODUCT_REVIEW.md"):
        assert (ROOT/doc).is_file(), doc
    subprocess.run(["git","diff","--check"],cwd=ROOT,check=True)
    print("Repository and public contracts passed.")


if __name__=="__main__": main()
