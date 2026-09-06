"""Shared service policy, validation and response deadlines; no AI or diagnosis."""
import json
import re
from datetime import date, datetime, time, timedelta
from pathlib import Path
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[1]
CATALOG = json.loads((ROOT / "VetAssistantHelpLine/Resources/service-catalog.json").read_text())
CATEGORIES = {item["id"]: item for item in CATALOG["categories"]}


def public_catalog():
    """Explicit client fields from the one catalog; new owner fields stay private."""
    result = {key: CATALOG[key] for key in (
        "version", "serviceName", "operatorName", "businessName", "supportEmail",
        "priceCents", "currency", "clarificationDays", "responseBusinessDays",
        "scope", "responsePromise", "coverage", "refundPolicy", "emergency", "privacyHint"
    )}
    result["categories"] = [{key: category[key] for key in (
        "id", "title", "summary", "prompt", "contextPrompt", "examples", "notIncluded"
    )} for category in CATALOG["categories"]]
    result["screening"] = [{key: item[key] for key in ("id", "text")} for item in CATALOG["screening"]]
    result["freeHelp"] = [{key: item[key] for key in ("title", "answer")} for item in CATALOG["freeHelp"]]
    return result


PACIFIC = ZoneInfo("America/Los_Angeles")
# Extra conservative routing, NOT a medical classifier. Absence of a match never
# establishes eligibility. The customer attestations AND human review are required.
REVIEW_WORDS = re.compile(
    r"\b(vomit\w*|diarrh\w*|bleed\w*|blood|pain\w*|limp\w*|seiz\w*|poison\w*|"
    r"toxi\w*|ingest\w*|swallow\w*|chok\w*|breath\w*|collaps\w*|injur\w*|"
    r"wound\w*|symptom\w*|sick|dying|letharg\w*|pregnan\w*|post.?op\w*|"
    r"surger\w*|medicat\w*|dose\w*|dosage\w*|supplement\w*|prescri\w*|"
    r"aggress\w*|biting|bites|anxiet\w*|diagnos\w*|rash\w*|itch\w*|"
    r"infect\w*|diet\w*|calori\w*|ibuprofen|acetaminophen|gabapentin|"
    r"insulin|chocolate|grapes|raisins|xylitol|lilies|antifreeze)\b|"
    r"can.{0,16}wait|won.t eat|not eating|won.t drink|can.t (pee|urinate)|"
    r"not (peeing|urinating)|litter accidents|sudden.{0,20}change|broken nail",
    re.IGNORECASE,
)


class Invalid(ValueError):
    pass


def clean(value, minimum=0, maximum=2000):
    if not isinstance(value, str):
        raise Invalid("Please enter text in each required field.")
    value = value.strip()
    if not minimum <= len(value) <= maximum or re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", value):
        raise Invalid(f"Text must contain {minimum}–{maximum} characters, without control characters.")
    return value


def validate_question(data):
    if not isinstance(data, dict):
        raise Invalid("Invalid question form.")
    if data.get("catalogVersion") != CATALOG["version"]:
        raise Invalid("The service terms changed. Reload and review before paying.")
    if not isinstance(data.get("category"), str) or data["category"] not in CATEGORIES:
        raise Invalid("Choose one listed category.")
    confirmations = data.get("confirmations", {})
    if not isinstance(confirmations, dict) or any(
        confirmations.get(item["id"]) is not True for item in CATALOG["screening"]
    ):
        raise Invalid("Complete every safety, scope and purchase confirmation.")
    question = clean(data.get("question"), 20, 1500)
    context = clean(data.get("context", ""), 0, 600)
    if REVIEW_WORDS.search(question + " " + context):
        raise Invalid("This wording needs free scope support or a veterinarian, not checkout. " + CATALOG["emergency"])
    email = clean(data.get("email"), 3, 254)
    if not re.fullmatch(r"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}", email):
        raise Invalid("Enter a valid reply email address.")
    if email != data.get("emailConfirmation"):
        raise Invalid("The reply email addresses do not match.")
    if data.get("format") not in ("checklist", "explanation"):
        raise Invalid("Choose checklist or explanation.")
    return {"category": data["category"], "question": question, "context": context,
            "email": email, "format": data["format"], "catalogVersion": CATALOG["version"]}


def validate_answer(data):
    if data.get("reviewed") is not True:
        raise Invalid("Complete the human response-quality checklist first.")
    result = {key: clean(data.get(key), minimum, maximum) for key, minimum, maximum in (
        ("summary", 30, 1500), ("practical", 60, 4000), ("boundary", 20, 1200)
    )}
    sources = data.get("sources")
    if not isinstance(sources, list) or not 1 <= len(sources) <= 3:
        raise Invalid("Include one to three relevant sources you personally checked.")
    for source in sources:
        try:
            parsed = urlsplit(clean(source, 12, 600))
        except ValueError:
            raise Invalid("Use a complete, valid HTTPS source link.") from None
        if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
            raise Invalid("Sources must be public HTTPS links without credentials.")
    result["sources"] = sources
    if len(set(sources)) != len(sources):
        raise Invalid("Remove duplicate source links.")
    return result


def observed(day):
    return day + timedelta(days=-1 if day.weekday() == 5 else 1 if day.weekday() == 6 else 0)


def nth_weekday(year, month, weekday, n):
    first = date(year, month, 1)
    return first + timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))


def holidays(year):
    days = {observed(date(year, month, day)) for month, day in (
        (1, 1), (6, 19), (7, 4), (11, 11), (12, 25)
    )}
    days.add(observed(date(year + 1, 1, 1)))
    days.update({nth_weekday(year, 1, 0, 3), nth_weekday(year, 2, 0, 3),
                 nth_weekday(year, 9, 0, 1), nth_weekday(year, 10, 0, 2),
                 nth_weekday(year, 11, 3, 4)})
    last_may = date(year, 5, 31)
    days.add(last_may - timedelta(days=last_may.weekday()))
    return days


def response_due(timestamp):
    day = datetime.fromtimestamp(timestamp, PACIFIC).date()
    remaining = CATALOG["responseBusinessDays"]
    while remaining:
        day += timedelta(days=1)
        if day.weekday() < 5 and day not in holidays(day.year):
            remaining -= 1
    return int(datetime.combine(day, time(17), PACIFIC).timestamp())


def clarification_deadline(timestamp):
    day = datetime.fromtimestamp(timestamp, PACIFIC).date() + timedelta(days=CATALOG["clarificationDays"])
    return int(datetime.combine(day, time(23, 59, 59), PACIFIC).timestamp())
