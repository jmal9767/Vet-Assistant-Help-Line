"""Payment/authorization/obligation tests with signed webhooks and no real charges."""
import hashlib
import hmac
import json
import secrets
import tempfile
import threading
import time
import unittest
import uuid
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

import stripe
from server.app import create_app, digest, StripeGateway
from server.domain import CATALOG, PACIFIC, Invalid, validate_question, response_due, clarification_deadline

TOKEN = "a" * 64
ADMIN = {"Authorization": "Bearer " + TOKEN}
SECRET = "whsec_test_fixture_only"
ANSWER = {"summary": "Here is a clear way to organize your sitter handover.",
          "practical": "Use separate headings for contacts, agreed responsibilities, locations of everyday supplies, and check-in arrangements. Leave a box for each completed task.",
          "boundary": "Medical instructions belong with the treating clinic; this checklist does not assess an animal or caregiver.",
          "sources": ["https://www.avma.org/resources-tools/pet-owners/petcare"], "reviewed": True}


class FakeStripe:
    def __init__(self):
        self.sessions = {}
        self.payments = {}
        self.created = 0
        self.refunds = 0
        self.refund_state = "succeeded"
    def create_checkout(self, q, base, token):
        key = "cs_test_" + q["id"]
        if key not in self.sessions:
            self.created += 1
            self.sessions[key] = {"id": key, "url": "https://checkout.stripe.com/c/pay/" + key,
                "metadata": {"question_id": q["id"]}, "client_reference_id": q["id"],
                "mode": "payment", "livemode": False, "amount_total": 999, "currency": "usd",
                "status": "open", "payment_status": "unpaid", "payment_intent": "pi_" + q["id"]}
        return self.sessions[key]
    def session(self, key):
        return self.sessions[key]
    def payment(self, key):
        return self.payments[key]
    def complete(self, key):
        session = self.sessions[key]
        session.update(status="complete", payment_status="paid")
        self.payments[session["payment_intent"]] = {"status": "succeeded", "livemode": False,
            "currency": "usd", "amount_received": 999,
            "latest_charge": {"created": int(time.time()), "refunded": False, "amount_refunded": 0, "disputed": False}}
    def refund(self, q):
        self.refunds += 1
        if self.refund_state == "succeeded":
            self.payments[q["payment_intent"]]["latest_charge"].update(refunded=True, amount_refunded=999)
        return {"id": "re_" + q["id"], "status": self.refund_state}
    def refund_status(self, key):
        return {"id": key, "status": self.refund_state}


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.gateway = FakeStripe()
        self.config = {"TESTING": True, "DATABASE": str(Path(self.directory.name)/"service.sqlite3"),
            "BASE_URL": "https://helpline.example", "ADMIN_HASH": digest(TOKEN),
            "RATE_KEY": "r"*64, "WEBHOOK_SECRET": SECRET, "LIVE": False}
        self.app = create_app(self.config, gateway=self.gateway)
        self.client = self.app.test_client()
        self.client.post("/api/admin/availability", json={"accepting": True}, headers=ADMIN)

    def payload(self, **changes):
        data = {"id": str(uuid.uuid4()), "token": secrets.token_hex(32), "catalogVersion": CATALOG["version"],
            "category": "organization", "question": "What headings should I use in a nonmedical sitter handover?",
            "context": "An organized list for a family member.", "email": "parent@example.com", "emailConfirmation": "parent@example.com",
            "format": "checklist", "confirmations": {x["id"]: True for x in CATALOG["screening"]}}
        data.update(changes)
        return data
    def headers(self, data):
        return {"X-Question-Token": data["token"]}
    def post(self, data, suffix, body=None, admin=False):
        return self.client.post(("/api/admin/questions/" if admin else "/api/questions/")+data["id"]+suffix,
            json=body or {}, headers=ADMIN if admin else self.headers(data))
    def get(self, data):
        return self.client.get("/api/questions/"+data["id"], headers=self.headers(data)).get_json()
    def webhook(self, kind, obj, event_id=None, **changes):
        event = {"id": event_id or "evt_"+uuid.uuid4().hex, "object": "event", "created": int(time.time()),
                 "type": kind, "livemode": False, "data": {"object": obj}}
        event.update(changes)
        payload = json.dumps(event).encode()
        timestamp = str(int(time.time()))
        signature = hmac.new(SECRET.encode(), timestamp.encode()+b"."+payload, hashlib.sha256).hexdigest()
        return self.client.post("/api/stripe/webhook", data=payload,
            headers={"Stripe-Signature": f"t={timestamp},v1={signature}", "Content-Type": "application/json"})
    def paid(self):
        data = self.payload()
        self.assertEqual(self.client.post("/api/questions", json=data).status_code, 201)
        self.assertEqual(self.post(data,"/checkout").status_code, 200)
        key = "cs_test_"+data["id"]
        self.gateway.complete(key)
        self.assertEqual(self.webhook("checkout.session.completed", {"id": key}).status_code, 200)
        return data
    def publish(self, data, **changes):
        body = dict(ANSWER, version=self.get(data)["version"])
        body.update(changes)
        return self.post(data,"/answer",body,admin=True)

    def test_all_15_examples_fit_their_own_intake(self):
        examples = []
        for category in CATALOG["categories"]:
            for example in category["examples"]:
                with self.subTest(example=example):
                    validate_question(self.payload(category=category["id"], question=example, context=""))
                    examples.append(example)
        self.assertEqual(len(examples), 15)
        self.assertEqual(len(set(examples)), 15)

    def test_medical_and_emergency_examples_never_reach_payment(self):
        for question in ["My cat can't pee. What should I do?", "My dog ate chocolate an hour ago.",
            "What dose of gabapentin should I give?", "My dog keeps vomiting. Can this wait?",
            "There is a broken nail. How can I trim it?", "Can you plan a diet for my cat?",
            "My dog has separation anxiety. What should I do?"]:
            with self.subTest(question=question):
                self.assertEqual(self.client.post("/api/questions", json=self.payload(question=question)).status_code, 422)
        self.assertEqual(self.gateway.created, 0)

    def test_attestations_price_and_category_cannot_be_bypassed(self):
        for changes in [{"confirmations": {}}, {"category": "medical"}, {"catalogVersion": "old"},
                        {"email": "parent@example.com\r\nBcc: victim@example.com"}, {"question": "x"*1501}]:
            self.assertEqual(self.client.post("/api/questions", json=self.payload(**changes)).status_code, 422)
        data = self.payload(priceCents=1, paid=True)
        self.client.post("/api/questions", json=data)
        self.assertEqual(self.get(data)["amount"], 999)
        self.assertEqual(self.get(data)["state"], "pending")

    def test_public_and_operator_credentials_are_separate(self):
        data = self.paid()
        self.assertEqual(self.client.get("/api/admin/questions", headers=self.headers(data)).status_code,401)
        self.assertEqual(self.client.get("/api/questions/"+data["id"],headers=ADMIN).status_code,404)
        public = self.get(data)
        for secret in ("payment_intent", "token_hash", "mail_state", "fingerprint", "session"):
            self.assertNotIn(secret, public)
        self.assertEqual(self.post(data,"/answer",ANSWER).status_code,404)

    def test_duplicate_draft_checkout_webhook_and_answer_are_idempotent(self):
        data = self.paid()
        self.assertEqual(self.client.post("/api/questions",json=data).status_code,200)
        other = dict(data,id=str(uuid.uuid4()),token=secrets.token_hex(32))
        self.assertEqual(self.client.post("/api/questions",json=other).status_code,409)
        version = self.get(data)["version"]
        self.webhook("checkout.session.completed",{"id":"cs_test_"+data["id"]},event_id="evt_repeat")
        self.webhook("checkout.session.completed",{"id":"cs_test_"+data["id"]},event_id="evt_repeat")
        self.assertEqual(self.get(data)["version"],version)
        body=dict(ANSWER,version=version)
        self.assertEqual(self.post(data,"/answer",body,admin=True).status_code,200)
        self.assertEqual(self.post(data,"/answer",body,admin=True).status_code,200)
        self.assertEqual(self.gateway.created,1)

    def test_checkout_retries_use_the_same_session(self):
        data=self.payload();self.client.post("/api/questions",json=data)
        one=self.post(data,"/checkout").get_json();two=self.post(data,"/checkout").get_json()
        self.assertEqual(one,two);self.assertEqual(self.gateway.created,1)
        self.assertEqual(self.client.get("/api/admin/questions",headers=ADMIN).get_json()["questions"],[])

    def test_webhook_signature_and_payment_amount_are_verified(self):
        self.assertEqual(self.client.post("/api/stripe/webhook",json={"paid":True}).status_code,400)
        data=self.payload();self.client.post("/api/questions",json=data);self.post(data,"/checkout")
        key="cs_test_"+data["id"];self.gateway.complete(key)
        self.gateway.sessions[key]["amount_total"]=1
        self.assertEqual(self.webhook("checkout.session.completed",{"id":key}).status_code,400)
        with self.app.extensions["database"]() as c:
            self.assertEqual(c.execute("SELECT state FROM questions").fetchone()[0],"pending")

    def test_delayed_webhook_recovers_from_verified_stripe_session(self):
        data=self.payload();self.client.post("/api/questions",json=data);self.post(data,"/checkout")
        self.gateway.complete("cs_test_"+data["id"])
        self.assertEqual(self.get(data)["state"],"paid")

    def test_refund_request_wins_over_stale_answer(self):
        data=self.paid();old=self.get(data)["version"]
        self.assertEqual(self.post(data,"/refund-request").status_code,200)
        self.assertEqual(self.post(data,"/answer",dict(ANSWER,version=old),admin=True).status_code,409)
        self.assertIsNone(self.get(data)["answer"])
        result=self.post(data,"/refund",{"confirmed":True,"note":"Full refund for a cancelled question."},admin=True)
        self.assertEqual(result.status_code,200);self.assertEqual(result.get_json()["state"],"refunded")
        self.post(data,"/refund",{"confirmed":True,"note":"Full refund for a cancelled question."},admin=True)
        self.assertEqual(self.gateway.refunds,1)

    def test_pending_refund_never_reopens_for_an_answer(self):
        data=self.paid();self.gateway.refund_state="pending";self.post(data,"/refund-request")
        body={"confirmed":True,"note":"Full refund for a cancelled question."}
        self.post(data,"/refund",body,admin=True)
        self.webhook("refund.updated",{"payment_intent":"pi_"+data["id"]})
        q=self.get(data)
        result=self.post(data,"/reconcile",{"version":q["version"]},admin=True)
        self.assertEqual(result.get_json()["state"],"refund_requested")
        self.post(data,"/refund",body,admin=True)
        self.assertEqual(self.gateway.refunds,1)
        self.assertEqual(self.publish(data).status_code,409)

    def test_charge_dispute_or_refund_blocks_publishing(self):
        data=self.paid();payment=self.gateway.payments["pi_"+data["id"]]
        payment["latest_charge"]["disputed"]=True
        self.assertEqual(self.publish(data).status_code,409)
        payment["latest_charge"].update(disputed=False,refunded=True,amount_refunded=999)
        self.assertEqual(self.publish(data).status_code,409)

    def test_one_clarification_is_included_and_idempotent(self):
        data=self.paid();self.assertEqual(self.publish(data).status_code,200)
        body={"text":"Can you explain how the check-in heading would look?","sameTopic":True}
        first=self.post(data,"/clarification",body);second=self.post(data,"/clarification",body)
        self.assertEqual(first.status_code,200);self.assertEqual(first.get_json()["version"],second.get_json()["version"])
        self.assertEqual(self.post(data,"/clarification",dict(body,text="Could you explain a different heading too?")).status_code,409)
        result=self.publish(data,summary="The check-in heading can record an agreed time and a contact method.")
        self.assertEqual(result.status_code,200);self.assertEqual(result.get_json()["state"],"closed")
        self.assertEqual(self.gateway.created,1)

    def test_clarification_deadline_and_medical_boundary(self):
        data=self.paid();self.publish(data)
        self.assertEqual(self.post(data,"/clarification",{"text":"Can I give a dose of medication?","sameTopic":True}).status_code,422)
        deadline=self.get(data)["clarification_deadline"]
        with patch("server.app.time.time",return_value=deadline+1):
            self.assertEqual(self.post(data,"/clarification",{"text":"Can you explain the checklist headings?","sameTopic":True}).status_code,409)

    def test_mail_handoff_survives_restart_and_blocks_duplicate_copy(self):
        data=self.paid();q=self.publish(data).get_json()
        q=self.post(data,"/mail",{"version":q["version"],"action":"begin"},admin=True).get_json()
        self.assertEqual(q["mail_state"],"unresolved")
        self.assertEqual(self.post(data,"/mail",{"version":q["version"],"action":"begin"},admin=True).status_code,409)
        restarted=create_app(self.config,gateway=self.gateway).test_client()
        self.assertEqual(restarted.get("/api/admin/questions",headers=ADMIN).get_json()["questions"][0]["mail_state"],"unresolved")
        self.assertEqual(self.post(data,"/mail",{"version":q["version"],"action":"deleted","confirmed":False},admin=True).status_code,409)
        result=self.post(data,"/mail",{"version":q["version"],"action":"queued","confirmed":True},admin=True)
        self.assertEqual(result.get_json()["mail_state"],"queued")

    def test_queue_pauses_and_limits_reservations(self):
        self.app.config["MAX_OPEN"]=1
        data=self.payload();self.client.post("/api/questions",json=data)
        self.assertFalse(self.client.get("/api/catalog").get_json()["accepting"])
        self.assertEqual(self.client.post("/api/questions",json=self.payload(question="How can I organize the household contact list?")).status_code,503)
        self.client.post("/api/admin/availability",json={"accepting":False},headers=ADMIN)
        self.assertEqual(self.post(data,"/checkout").status_code,503)

    def test_request_origin_and_static_files_do_not_expose_server(self):
        self.assertEqual(self.client.post("/api/questions",json=self.payload(),headers={"Origin":"https://attacker.example"}).status_code,403)
        for path in ("/server/app.py","/.git/config","/README.md","/service.sqlite3"):
            self.assertEqual(self.client.get(path).status_code,404)
        for path in ("/","/status.html","/terms.html","/privacy.html","/site.css","/intake.js","/status.js","/brand.png"):
            result=self.client.get(path)
            self.assertEqual(result.status_code,200,path)
            self.assertEqual(result.headers["Cache-Control"],"no-store")
            result.close()

    def test_live_test_database_separation(self):
        with self.assertRaises(RuntimeError):
            create_app(dict(self.config,LIVE=True),gateway=self.gateway)

    def test_retention_preserves_uncertain_payments_and_unfinished_replies(self):
        data=self.paid();self.publish(data)
        unknown=self.payload(question="What goes into a household contacts organizer?")
        self.client.post("/api/questions",json=unknown)
        with patch("server.app.time.time",return_value=time.time()+100*86400):
            result=self.app.test_cli_runner().invoke(args=["purge-expired"])
            self.assertEqual(result.exit_code,0,result.output)
        with self.app.extensions["database"]() as c:
            self.assertEqual(c.execute("SELECT count(*) FROM questions").fetchone()[0],2)

    def test_cancellation_during_stripe_lookup_prevents_publication(self):
        data=self.paid();body=dict(ANSWER,version=self.get(data)["version"])
        started=threading.Event();resume=threading.Event();results=[]
        original=self.gateway.payment
        def delayed(key):
            started.set()
            if not resume.wait(3): raise AssertionError("Test synchronization timed out")
            return original(key)
        self.gateway.payment=delayed
        def publish():
            client=self.app.test_client()
            results.append(client.post("/api/admin/questions/"+data["id"]+"/answer",json=body,headers=ADMIN).status_code)
        thread=threading.Thread(target=publish)
        thread.start()
        try:
            self.assertTrue(started.wait(3))
            self.assertEqual(self.post(data,"/refund-request").status_code,200)
        finally:
            resume.set();thread.join(3)
        self.assertEqual(results,[409])
        self.assertIsNone(self.get(data)["answer"])

    def test_new_answer_cannot_overwrite_an_unresolved_mail_copy(self):
        data=self.paid();q=self.publish(data).get_json()
        self.post(data,"/mail",{"version":q["version"],"action":"begin"},admin=True)
        self.post(data,"/clarification",{"text":"Please explain the checklist headings further.","sameTopic":True})
        self.assertEqual(self.publish(data,summary="Here is another explanation of the organizer headings.").status_code,409)

    def test_malformed_fields_are_validation_errors(self):
        self.assertEqual(self.client.post("/api/questions",json=self.payload(category=[])).status_code,422)
        data=self.paid()
        self.assertEqual(self.publish(data,sources=["https://[malformed.example"]).status_code,422)
        self.assertEqual(self.publish(data,sources=ANSWER["sources"]*2).status_code,422)


class DeadlineTests(unittest.TestCase):
    def stamp(self, value): return int(datetime.fromisoformat(value).replace(tzinfo=PACIFIC).timestamp())
    def test_weekend_and_labor_day(self):
        self.assertEqual(response_due(self.stamp("2026-09-04T18:30:00")),self.stamp("2026-09-09T17:00:00"))
    def test_observed_new_year_on_previous_year(self):
        self.assertEqual(response_due(self.stamp("2021-12-30T10:00:00")),self.stamp("2022-01-04T17:00:00"))
    def test_daylight_saving_uses_calendar_days(self):
        self.assertEqual(clarification_deadline(self.stamp("2026-03-06T12:00:00")),self.stamp("2026-03-13T23:59:59"))


class StripeContractTests(unittest.TestCase):
    def test_installed_sdk_decodes_nested_objects_from_transport(self):
        gateway=StripeGateway("sk_test_fixture_only")
        payload={"object":"payment_intent","id":"pi_fixture","livemode":False,"status":"succeeded",
            "amount_received":999,"currency":"usd","latest_charge":{"object":"charge","id":"ch_fixture","created":1788700000,"refunded":False}}
        client=stripe.default_http_client
        with patch.object(client,"request",return_value=(json.dumps(payload),200,{})) as network:
            payment=gateway.payment("pi_fixture")
            self.assertIsInstance(payment,dict)
            self.assertIsInstance(payment["latest_charge"],dict)
            self.assertEqual(payment["amount_received"],999)
            self.assertEqual(network.call_count,1)

    def test_locked_sdk_checkout_and_refund_contract(self):
        gateway=StripeGateway("sk_test_fixture_only")
        q={"id":"fixture", "payload":json.dumps({"email":"parent@example.com"}), "currency":"usd","amount":999,"created":int(time.time()),"payment_intent":"pi_fixture"}
        with patch.object(stripe.checkout.Session,"create",return_value=stripe.checkout.Session.construct_from({"id":"cs_fixture"},"sk_test_fixture_only")) as call:
            gateway.create_checkout(q,"https://helpline.example","b"*64)
            values=call.call_args.kwargs
            self.assertEqual(values["line_items"][0]["price_data"]["unit_amount"],999)
            self.assertEqual(values["payment_method_types"],["card"])
            self.assertEqual(values["idempotency_key"],"question-checkout-fixture")
            self.assertEqual(values["success_url"],values["cancel_url"])
            self.assertNotIn("question",json.dumps(values["metadata"]).replace("question_id","reference"))
        with patch.object(stripe.Refund,"create",return_value=stripe.Refund.construct_from({"id":"re_fixture"},"sk_test_fixture_only")) as call:
            gateway.refund(q)
            self.assertEqual(call.call_args.kwargs["amount"],999)
            self.assertEqual(call.call_args.kwargs["payment_intent"],"pi_fixture")


if __name__ == "__main__": unittest.main()
