"""Private operator API + public intake. Deploy behind HTTPS; never serve repo root."""
import hashlib
import hmac
import json
import os
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from urllib.parse import urlsplit

import stripe
from flask import Flask, abort, jsonify, request, send_file
from werkzeug.exceptions import HTTPException

from server.domain import (CATALOG, ROOT, Invalid, clean, validate_question,
                           validate_answer, response_due, clarification_deadline,
                           REVIEW_WORDS)

SCHEMA = """
CREATE TABLE IF NOT EXISTS questions (
 id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, fingerprint TEXT NOT NULL,
 payload TEXT NOT NULL, created INTEGER NOT NULL, paid_at INTEGER,
 due INTEGER, state TEXT NOT NULL DEFAULT 'pending', version INTEGER NOT NULL DEFAULT 0,
 session TEXT UNIQUE, checkout_url TEXT, payment_intent TEXT UNIQUE,
 amount INTEGER NOT NULL, currency TEXT NOT NULL, answer TEXT, answer_at INTEGER,
 clarification TEXT, clarification_at INTEGER, clarification_answer TEXT,
 clarification_due INTEGER, clarification_deadline INTEGER, refund_id TEXT, refund_requested_at INTEGER,
 note TEXT NOT NULL DEFAULT '', mail_state TEXT NOT NULL DEFAULT 'none', updated INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_questions_state_due ON questions(state, due);
CREATE INDEX IF NOT EXISTS idx_questions_fingerprint_created ON questions(fingerprint, created);
CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS settings (id INTEGER PRIMARY KEY CHECK(id=1), accepting INTEGER NOT NULL DEFAULT 0);
INSERT OR IGNORE INTO settings(id, accepting) VALUES(1, 0);
CREATE TABLE IF NOT EXISTS limits (key TEXT PRIMARY KEY, count INTEGER NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS environment (id INTEGER PRIMARY KEY CHECK(id=1), live INTEGER NOT NULL);
"""


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class StripeGateway:
    def __init__(self, key):
        self.key = key
        stripe.default_http_client = stripe.RequestsClient(timeout=15)

    def create_checkout(self, q, base, token):
        payload = json.loads(q["payload"])
        link = f"{base}/status.html#{q['id']}/{token}"
        return stripe.checkout.Session.create(
            api_key=self.key, mode="payment", payment_method_types=["card"],
            client_reference_id=q["id"], customer_email=payload["email"],
            metadata={"question_id": q["id"]},
            payment_intent_data={"metadata": {"question_id": q["id"]}},
            line_items=[{"price_data": {"currency": q["currency"],
                "unit_amount": q["amount"], "product_data": {
                    "name": "One nonmedical education answer",
                    "description": "Human-written answer and one same-topic clarification; not veterinary care."
                }}, "quantity": 1}],
            success_url=link, cancel_url=link, expires_at=q["created"] + 3600,
            idempotency_key=f"question-checkout-{q['id']}",
        ).to_dict()

    def session(self, session_id):
        return stripe.checkout.Session.retrieve(session_id, api_key=self.key).to_dict()

    def payment(self, intent_id):
        return stripe.PaymentIntent.retrieve(intent_id, expand=["latest_charge"], api_key=self.key).to_dict()

    def refund(self, q):
        return stripe.Refund.create(payment_intent=q["payment_intent"],
            amount=q["amount"], metadata={"question_id": q["id"]},
            idempotency_key=f"question-full-refund-{q['id']}", api_key=self.key).to_dict()

    def refund_status(self, refund_id):
        return stripe.Refund.retrieve(refund_id, api_key=self.key).to_dict()


def create_app(config=None, gateway=None):
    app = Flask(__name__, static_folder=None)
    app.config.update(
        MAX_CONTENT_LENGTH=24_000,
        DATABASE=os.environ.get("HELPLINE_DATABASE", ""),
        BASE_URL=os.environ.get("HELPLINE_BASE_URL", ""),
        ADMIN_HASH=os.environ.get("HELPLINE_ADMIN_TOKEN_SHA256", ""),
        RATE_KEY=os.environ.get("HELPLINE_RATE_KEY", ""),
        STRIPE_KEY=os.environ.get("STRIPE_SECRET_KEY", ""),
        WEBHOOK_SECRET=os.environ.get("STRIPE_WEBHOOK_SECRET", ""),
        LIVE=os.environ.get("HELPLINE_LIVE", "false") == "true",
        MAX_OPEN=10,
    )
    if config:
        app.config.update(config)
    base = app.config["BASE_URL"].rstrip("/")
    parsed = urlsplit(base)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise RuntimeError("HELPLINE_BASE_URL must be the public HTTPS service URL.")
    if not re.fullmatch(r"[a-f0-9]{64}", app.config["ADMIN_HASH"]):
        raise RuntimeError("Set HELPLINE_ADMIN_TOKEN_SHA256 from a random private device token.")
    if len(app.config["RATE_KEY"]) < 32:
        raise RuntimeError("Set a separate random HELPLINE_RATE_KEY.")
    if gateway is None:
        expected = "sk_live_" if app.config["LIVE"] else "sk_test_"
        if not app.config["STRIPE_KEY"].startswith(expected) or not app.config["WEBHOOK_SECRET"].startswith("whsec_"):
            raise RuntimeError("Stripe credentials must match the configured live/test environment.")
    database = Path(app.config["DATABASE"])
    if not database.is_absolute() or database.is_symlink() or ROOT in database.resolve().parents:
        raise RuntimeError("Database must be an absolute path on private storage outside the checkout.")
    database.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if database.parent.stat().st_mode & 0o077:
        raise RuntimeError("The database directory must be private (0700).")
    fd = os.open(database, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    os.close(fd)
    if database.stat().st_mode & 0o077:
        raise RuntimeError("Database must be private (0600).")
    pay = gateway or StripeGateway(app.config["STRIPE_KEY"])

    @contextmanager
    def db():
        connection = sqlite3.connect(database, timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA secure_delete=ON")
        try:
            connection.execute("BEGIN IMMEDIATE")
            yield connection
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        finally:
            connection.close()

    with db() as c:
        c.executescript(SCHEMA)
        c.execute("INSERT OR IGNORE INTO environment VALUES(1,?)", (int(app.config["LIVE"]),))
        if bool(c.execute("SELECT live FROM environment WHERE id=1").fetchone()[0]) != app.config["LIVE"]:
            raise RuntimeError("Live and test services must use separate databases.")
    app.extensions["database"] = db

    def now():
        return int(time.time())

    def admin():
        token = request.headers.get("Authorization", "")
        if not token.startswith("Bearer ") or not hmac.compare_digest(digest(token[7:]), app.config["ADMIN_HASH"]):
            abort(401)

    def fetch_question(c, question_id, authenticated=False):
        q = c.execute("SELECT * FROM questions WHERE id=?", (question_id,)).fetchone()
        if not q:
            abort(404)
        if not authenticated:
            token = request.headers.get("X-Question-Token", "")
            if not hmac.compare_digest(q["token_hash"], digest(token)):
                abort(404)
        return q

    def version(q, data):
        if type(data.get("version")) is not int or q["version"] != data["version"]:
            abort(409, description="This question changed. Refresh before trying again.")

    def serialized(q, private=False):
        keys = ("id", "created", "paid_at", "due", "state", "version", "amount", "currency",
                "answer_at", "clarification", "clarification_at", "clarification_due",
                "clarification_deadline", "note", "mail_state", "updated")
        result = {k: q[k] for k in keys}
        result.update(json.loads(q["payload"]))
        for key in ("answer", "clarification_answer"):
            result[key] = json.loads(q[key]) if q[key] else None
        if private:
            result["payment_intent"] = q["payment_intent"]
        else:
            result.pop("mail_state")
        return result

    def payment_state(q):
        payment = pay.payment(q["payment_intent"])
        charge = payment.get("latest_charge")
        if not isinstance(charge, dict) and not hasattr(charge, "get"):
            raise Invalid("Payment verification is unavailable. Do not answer or ask the client to pay again.")
        if payment.get("livemode") != app.config["LIVE"] or payment.get("currency") != q["currency"] or payment.get("amount_received") != q["amount"] or payment.get("status") != "succeeded":
            return "payment_hold"
        if charge.get("disputed"):
            return "payment_hold"
        if charge.get("refunded") and charge.get("amount_refunded") == q["amount"]:
            return "refunded"
        if charge.get("amount_refunded", 0):
            return "payment_hold"
        return "paid"

    @app.before_request
    def protect():
        if request.method in ("POST", "PUT", "DELETE") and request.path != "/api/stripe/webhook":
            origin = request.headers.get("Origin")
            expected = f"{parsed.scheme}://{parsed.netloc}"
            if origin and origin != expected:
                abort(403)
            if not request.is_json:
                abort(415)
            if not isinstance(request.get_json(silent=True), dict):
                abort(400, description="Request must contain a JSON object.")
        if request.path.startswith("/api/") and request.path != "/api/stripe/webhook":
            # Remote address only. Never trust a client-supplied forwarded IP.
            bucket = "checkout" if request.path == "/api/questions" else "api"
            identifier = hmac.new(app.config["RATE_KEY"].encode(),
                f"{request.remote_addr}:{bucket}:{now() // 60}".encode(), hashlib.sha256).hexdigest()
            with db() as c:
                c.execute("DELETE FROM limits WHERE expires<?", (now(),))
                c.execute("INSERT INTO limits VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=count+1", (identifier, now()+120))
                count = c.execute("SELECT count FROM limits WHERE key=?", (identifier,)).fetchone()[0]
            if count > (10 if bucket == "checkout" else 120):
                abort(429)

    @app.after_request
    def headers(response):
        response.headers.update({"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
            "Referrer-Policy": "no-referrer", "X-Frame-Options": "DENY",
            "Strict-Transport-Security": "max-age=31536000",
            "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
            "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self' https://checkout.stripe.com"})
        return response

    @app.errorhandler(Invalid)
    def invalid(error):
        return jsonify(error=str(error)), 422

    @app.errorhandler(HTTPException)
    def http_error(error):
        return jsonify(error=error.description), error.code

    @app.errorhandler(stripe.StripeError)
    def stripe_error(error):
        # Never include keys, customer data, Stripe request bodies or exception text.
        return jsonify(error="Payment service unavailable. Keep your reference and retry; do not create another purchase."), 503

    @app.errorhandler(sqlite3.Error)
    def database_error(error):
        return jsonify(error="Service storage is temporarily unavailable. Please retry using your saved reference."), 503

    @app.get("/")
    def index():
        return send_file(ROOT / "index.html")

    @app.get("/<name>")
    def assets(name):
        allowed = {"index.html", "status.html", "privacy.html", "terms.html", "site.css", "intake.js", "status.js", "sw.js"}
        if name not in allowed:
            abort(404)
        return send_file(ROOT / name)

    @app.get("/brand.png")
    def brand():
        return send_file(ROOT / "VetAssistantHelpLine/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

    def accepting(c):
        enabled = bool(c.execute("SELECT accepting FROM settings WHERE id=1").fetchone()[0])
        count = c.execute("SELECT count(*) FROM questions WHERE state IN ('paid','clarification','refund_requested','payment_hold') OR (state='pending' AND created>?)", (now()-3600,)).fetchone()[0]
        return enabled and count < app.config["MAX_OPEN"]

    @app.get("/api/catalog")
    def catalog():
        with db() as c:
            return jsonify(**CATALOG, accepting=accepting(c), live=app.config["LIVE"])

    @app.post("/api/questions")
    def create_question():
        data = request.get_json()
        payload = validate_question(data)
        try:
            question_id = str(uuid.UUID(data.get("id", "")))
        except (ValueError, TypeError, AttributeError):
            raise Invalid("Invalid question reference. Reload the form.")
        token = data.get("token", "")
        if not isinstance(token, str) or not re.fullmatch(r"[a-f0-9]{64}", token):
            raise Invalid("Invalid private receipt key. Reload the form.")
        encoded = json.dumps(payload, sort_keys=True)
        fingerprint = hmac.new(app.config["RATE_KEY"].encode(), encoded.encode(), hashlib.sha256).hexdigest()
        with db() as c:
            previous = c.execute("SELECT * FROM questions WHERE id=?", (question_id,)).fetchone()
            if previous:
                if previous["token_hash"] != digest(token) or previous["payload"] != encoded:
                    abort(409, description="This reference already belongs to a different draft.")
                return jsonify(id=question_id)
            if not accepting(c):
                return jsonify(error="New questions are paused or the queue is full. No payment was taken.",resetDraft=True),503
            if c.execute("SELECT 1 FROM questions WHERE fingerprint=? AND created>? AND state NOT IN ('refunded','expired')", (fingerprint, now()-86400)).fetchone():
                abort(409, description="This question already has a submission. Use the saved private link or contact free support; do not pay twice.")
            c.execute("INSERT INTO questions(id,token_hash,fingerprint,payload,created,updated,amount,currency) VALUES(?,?,?,?,?,?,?,?)",
                (question_id,digest(token),fingerprint,encoded,now(),now(),CATALOG["priceCents"],CATALOG["currency"]))
        return jsonify(id=question_id), 201

    @app.post("/api/questions/<question_id>/checkout")
    def checkout(question_id):
        with db() as c:
            q = fetch_question(c, question_id)
            if q["state"] != "pending" or now() >= q["created"]+3600:
                abort(409, description="This checkout is paid or no longer available. Check your private receipt; do not pay again if charged.")
            if q["checkout_url"]:
                return jsonify(url=q["checkout_url"])
            if now() >= q["created"]+1800:
                abort(409, description="This draft is too old to start checkout. Contact free support if a payment may already exist.")
            if not c.execute("SELECT accepting FROM settings WHERE id=1").fetchone()[0]:
                abort(503, description="New checkout is paused. No new payment was requested.")
        session = pay.create_checkout(q, base, request.headers.get("X-Question-Token", ""))
        if urlsplit(session["url"]).hostname != "checkout.stripe.com" or urlsplit(session["url"]).scheme != "https":
            abort(503)
        with db() as c:
            c.execute("UPDATE questions SET session=?, checkout_url=? WHERE id=? AND (session IS NULL OR session=?)",
                (session["id"], session["url"], question_id, session["id"]))
        return jsonify(url=session["url"])

    def fulfill(session_id, timestamp):
        session = pay.session(session_id)
        question_id = session.get("metadata", {}).get("question_id")
        with db() as c:
            q = c.execute("SELECT * FROM questions WHERE id=?", (question_id,)).fetchone()
            if not q:
                return
            if session.get("livemode") != app.config["LIVE"] or session.get("mode") != "payment" or session.get("client_reference_id") != q["id"] or session.get("amount_total") != q["amount"] or session.get("currency") != q["currency"]:
                abort(400)
            if q["session"] and q["session"] != session_id:
                abort(409)
            if session.get("status") != "complete" or session.get("payment_status") != "paid":
                return
            intent = session.get("payment_intent")
            if not isinstance(intent, str) or not intent.startswith("pi_"):
                abort(400)
            c.execute("UPDATE questions SET state='paid',session=?,payment_intent=?,paid_at=?,due=?,updated=?,version=version+1 WHERE id=? AND state='pending'",
                (session_id,intent,timestamp,response_due(timestamp),now(),q["id"]))

    @app.post("/api/stripe/webhook")
    def webhook():
        try:
            event = stripe.Webhook.construct_event(request.get_data(), request.headers.get("Stripe-Signature", ""), app.config["WEBHOOK_SECRET"]).to_dict()
        except (ValueError, stripe.SignatureVerificationError):
            abort(400)
        if event.get("livemode") != app.config["LIVE"]:
            abort(400)
        with db() as c:
            if c.execute("SELECT 1 FROM events WHERE id=?", (event["id"],)).fetchone():
                return jsonify(received=True)
        if event["type"] in ("checkout.session.completed", "checkout.session.async_payment_succeeded"):
            fulfill(event["data"]["object"]["id"], event["created"])
        elif event["type"].startswith(("charge.refund", "charge.dispute", "refund.")):
            obj = event["data"]["object"]
            intent = obj.get("payment_intent")
            if intent:
                with db() as c:
                    c.execute("UPDATE questions SET state=CASE WHEN state='refunded' THEN state ELSE 'payment_hold' END,version=version+1,updated=? WHERE payment_intent=?", (now(),intent))
        with db() as c:
            c.execute("INSERT OR IGNORE INTO events VALUES(?,?)", (event["id"],now()))
        return jsonify(received=True)

    @app.get("/api/questions/<question_id>")
    def public_question(question_id):
        with db() as c:
            q = fetch_question(c,question_id)
        # Recover a delayed webhook using a fresh server-to-Stripe lookup.
        # A redirect or client-supplied payment status never authorizes an answer.
        if q["state"] == "pending" and q["session"]:
            session = pay.session(q["session"])
            if session.get("status") == "expired" and session.get("payment_status") == "unpaid":
                with db() as c:
                    c.execute("UPDATE questions SET state='expired',updated=?,version=version+1 WHERE id=? AND state='pending'", (now(),question_id))
            if session.get("status") == "complete" and session.get("payment_status") == "paid":
                payment = pay.payment(session["payment_intent"])
                charge = payment.get("latest_charge")
                if payment.get("status") == "succeeded" and charge and charge.get("created"):
                    fulfill(q["session"], int(charge["created"]))
        with db() as c:
            return jsonify(serialized(fetch_question(c,question_id)))

    @app.post("/api/questions/<question_id>/clarification")
    def clarify(question_id):
        data = request.get_json()
        text = clean(data.get("text"), 15, 1200)
        if data.get("sameTopic") is not True or REVIEW_WORDS.search(text):
            raise Invalid("Use free support for a scope question or contact a veterinarian for medical concerns. A clarification must explain the original nonmedical answer, not introduce a new issue.")
        with db() as c:
            q = fetch_question(c,question_id)
            if q["clarification"] == text:
                return jsonify(serialized(q))
            if q["state"] != "answered" or q["clarification"] or now() > q["clarification_deadline"]:
                abort(409, description="The included clarification is already used, closed, or past its deadline. Free administrative support remains available.")
            c.execute("UPDATE questions SET state='clarification',clarification=?,clarification_at=?,clarification_due=?,version=version+1,updated=? WHERE id=?", (text,now(),response_due(now()),now(),question_id))
            return jsonify(serialized(fetch_question(c,question_id)))

    @app.post("/api/questions/<question_id>/refund-request")
    def request_refund(question_id):
        with db() as c:
            q = fetch_question(c,question_id)
            if q["answer"]:
                abort(409,description="An answer has already been published. Contact free support for a service or payment concern.")
            if q["state"] == "refund_requested":
                return jsonify(serialized(q))
            if q["state"] != "paid":
                abort(409)
            c.execute("UPDATE questions SET state='refund_requested',refund_requested_at=?,note='Client requested cancellation before answer.',version=version+1,updated=? WHERE id=?",(now(),now(),question_id))
            return jsonify(serialized(fetch_question(c,question_id)))

    @app.get("/api/admin/questions")
    def inbox():
        admin()
        with db() as c:
            # All unfinished obligations first; completed history cannot hide them.
            rows = c.execute("SELECT * FROM questions WHERE state NOT IN ('pending','expired') ORDER BY CASE WHEN state IN ('paid','clarification','refund_requested','payment_hold') OR mail_state IN ('pending','unresolved') THEN 0 ELSE 1 END, COALESCE(clarification_due,due),created").fetchall()
            enabled = bool(c.execute("SELECT accepting FROM settings WHERE id=1").fetchone()[0])
            return jsonify(questions=[serialized(q,True) for q in rows], accepting=enabled, live=app.config["LIVE"])

    @app.post("/api/admin/availability")
    def availability():
        admin()
        enabled = request.get_json().get("accepting")
        if type(enabled) is not bool:
            abort(422)
        with db() as c:
            c.execute("UPDATE settings SET accepting=? WHERE id=1",(int(enabled),))
        return jsonify(accepting=enabled)

    @app.post("/api/admin/questions/<question_id>/answer")
    def answer(question_id):
        admin()
        data = request.get_json()
        answer_text = json.dumps(validate_answer(data),sort_keys=True)
        with db() as c:
            q = fetch_question(c,question_id,True)
            field = "clarification_answer" if q["clarification"] else "answer"
            if q[field] == answer_text:
                return jsonify(serialized(q,True))
            version(q,data)
            if q["mail_state"] == "unresolved":
                abort(409,description="Resolve the existing email handoff before publishing another answer.")
            if q["state"] not in ("paid","clarification"):
                abort(409,description="Only a paid, open question can be answered. Resolve any refund or payment hold first.")
        if payment_state(q) != "paid":
            abort(409,description="Payment is refunded, disputed, or unverified. Reconcile it before answering.")
        with db() as c:
            q = fetch_question(c,question_id,True)
            version(q,data)
            if q["state"] == "paid":
                c.execute("UPDATE questions SET answer=?,answer_at=?,clarification_deadline=?,state='answered',mail_state='pending',updated=?,version=version+1 WHERE id=?",
                    (answer_text,now(),clarification_deadline(now()),now(),question_id))
            elif q["state"] == "clarification":
                c.execute("UPDATE questions SET clarification_answer=?,state='closed',mail_state='pending',updated=?,version=version+1 WHERE id=?",(answer_text,now(),question_id))
            else:
                abort(409)
            return jsonify(serialized(fetch_question(c,question_id,True),True))

    @app.post("/api/admin/questions/<question_id>/refund")
    def refund(question_id):
        admin()
        data = request.get_json()
        if data.get("confirmed") is not True:
            abort(422)
        note = clean(data.get("note"),20,1200)
        with db() as c:
            q = fetch_question(c,question_id,True)
            if q["state"] == "refunded":
                return jsonify(serialized(q,True))
            if not q["payment_intent"]:
                abort(409)
            if q["state"] != "refund_requested":
                version(q,data)
            c.execute("UPDATE questions SET state='refund_requested',refund_requested_at=COALESCE(refund_requested_at,?),note=?,version=version+1,updated=? WHERE id=?",(now(),note,now(),question_id))
        current = payment_state(q)
        if current == "refunded":
            with db() as c:
                c.execute("UPDATE questions SET state='refunded',updated=? WHERE id=?",(now(),question_id))
        elif current != "paid":
            abort(409,description="Payment is disputed or partially refunded. Reconcile in Stripe; do not refund twice.")
        else:
            refund_result = pay.refund_status(q["refund_id"]) if q["refund_id"] else pay.refund(q)
            state = "refunded" if refund_result["status"] == "succeeded" else "refund_requested"
            with db() as c:
                c.execute("UPDATE questions SET state=?,refund_id=?,updated=? WHERE id=?",(state,refund_result["id"],now(),question_id))
        with db() as c:
            return jsonify(serialized(fetch_question(c,question_id,True),True))

    @app.post("/api/admin/questions/<question_id>/reconcile")
    def reconcile(question_id):
        admin()
        with db() as c:
            q = fetch_question(c,question_id,True)
            version(q,request.get_json())
        state = payment_state(q)
        if state == "paid":
            if q["refund_requested_at"]:
                state = "refund_requested"
            else:
                state = "closed" if q["clarification_answer"] else "clarification" if q["clarification"] else "answered" if q["answer"] else "paid"
        with db() as c:
            q = fetch_question(c,question_id,True)
            version(q,request.get_json())
            c.execute("UPDATE questions SET state=?,updated=?,version=version+1 WHERE id=?",(state,now(),question_id))
            return jsonify(serialized(fetch_question(c,question_id,True),True))

    @app.post("/api/admin/questions/<question_id>/mail")
    def mail_state(question_id):
        admin()
        data = request.get_json()
        action = data.get("action")
        with db() as c:
            q = fetch_question(c,question_id,True)
            version(q,data)
            if action == "begin" and q["mail_state"] == "pending" and q["answer"]:
                state = "unresolved"
            elif action in ("queued","deleted") and q["mail_state"] == "unresolved" and data.get("confirmed") is True:
                state = "queued" if action == "queued" else "pending"
            else:
                abort(409,description="Resolve the existing email handoff before preparing another copy.")
            c.execute("UPDATE questions SET mail_state=?,updated=?,version=version+1 WHERE id=?",(state,now(),question_id))
            return jsonify(serialized(fetch_question(c,question_id,True),True))

    @app.cli.command("purge-expired")
    def purge_expired():
        """Run daily. Outstanding paid obligations are never automatically purged."""
        with db() as c:
            pending = c.execute("SELECT * FROM questions WHERE state='pending' AND created<?", (now()-7*86400,)).fetchall()
        for q in pending:
            if not q["session"]:
                # A checkout-creation response may have been lost. Retain for
                # reconciliation instead of assuming no payment was possible.
                continue
            session = pay.session(q["session"])
            if session.get("status") == "complete":
                payment = pay.payment(session["payment_intent"])
                charge = payment.get("latest_charge")
                if charge and charge.get("created"):
                    fulfill(q["session"], int(charge["created"]))
            elif session.get("status") == "expired" and session.get("payment_status") == "unpaid":
                with db() as c:
                    c.execute("DELETE FROM questions WHERE id=? AND state='pending'", (q["id"],))
        with db() as c:
            c.execute("DELETE FROM questions WHERE state='expired' AND created<?",(now()-7*86400,))
            c.execute("DELETE FROM questions WHERE state IN ('answered','closed','refunded') AND mail_state NOT IN ('pending','unresolved') AND updated<?",(now()-90*86400,))
            c.execute("DELETE FROM events WHERE created<?",(now()-90*86400,))
        # SQLite secure_delete + encrypted-volume rotation/backup retention are deployment gates.
    return app
