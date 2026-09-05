import getpass
import io
import sqlite3
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from redeem_question_credit import (
    LEDGER_SCHEMA_VERSION,
    PRODUCT_ID,
    ProofRejectedError,
    VerificationUnavailableError,
    accepted_message,
    digest,
    ledger_key_fingerprint,
    load_jws,
    main,
    make_api_client,
    make_verifiers,
    normalized_uuid,
    parse_args,
    preflight_emailed_payload,
    redeem_once,
    verify_with_dependencies,
)


class RedemptionLedgerTests(unittest.TestCase):
    def test_invalid_cli_invocations_are_unavailable_not_proof_rejections(self):
        valid_arguments = [
            "redeem_question_credit.py",
            "--ledger",
            "/secure/redemptions.sqlite3",
            "--ledger-key-file",
            "/secure/redemption.key",
            "--private-key",
            "/secure/AuthKey_TEST.p8",
            "--key-id",
            "KEY123",
            "--issuer-id",
            "01234567-89ab-cdef-0123-456789abcdef",
            "--root-certificate",
            "/secure/AppleRootCA.cer",
        ]
        cases = {
            "missing required arguments": ["redeem_question_credit.py"],
            "invalid environment": valid_arguments
            + ["--environment", "NotAnEnvironment"],
            "invalid numeric app id": valid_arguments
            + ["--app-apple-id", "not-a-number"],
            "unknown flag": valid_arguments + ["--unknown-flag"],
        }

        for name, arguments in cases.items():
            with self.subTest(name=name), patch.object(sys, "argv", arguments):
                with self.assertRaises(VerificationUnavailableError):
                    parse_args()

        with patch.object(sys, "argv", ["redeem_question_credit.py"]), patch(
            "sys.stderr",
            new_callable=io.StringIO,
        ) as error_output:
            self.assertEqual(main(), 4)
            self.assertIn("UNAVAILABLE:", error_output.getvalue())
            self.assertNotIn("REJECTED:", error_output.getvalue())

    def test_cli_derives_references_instead_of_accepting_body_fields(self):
        with patch.object(
            sys,
            "argv",
            [
                "redeem_question_credit.py",
                "--ledger",
                "/secure/redemptions.sqlite3",
                "--ledger-key-file",
                "/secure/redemption.key",
                "--private-key",
                "/secure/AuthKey_TEST.p8",
                "--key-id",
                "KEY123",
                "--issuer-id",
                "01234567-89ab-cdef-0123-456789abcdef",
                "--root-certificate",
                "/secure/AppleRootCA.cer",
            ],
        ):
            arguments = parse_args()

        self.assertFalse(hasattr(arguments, "transaction_id"))
        self.assertFalse(hasattr(arguments, "submission_reference"))

    def test_api_client_receives_private_key_as_bytes(self):
        captured = {}

        class FakeClient:
            def __init__(self, *arguments):
                captured["arguments"] = arguments

        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory) / "AuthKey_TEST.p8"
            fake_key = b"-----BEGIN " b"PRIVATE KEY-----\ntest\n"
            key_path.write_bytes(fake_key)
            key_path.chmod(0o600)

            make_api_client(
                FakeClient,
                key_path,
                "KEY123",
                "issuer-id",
                "com.example.app",
                "Production",
            )

        self.assertIsInstance(captured["arguments"][0], bytes)
        self.assertEqual(
            captured["arguments"][0],
            fake_key,
        )

    def test_jws_file_requires_private_regular_bounded_utf8_input(self):
        with tempfile.TemporaryDirectory() as directory:
            directory_path = Path(directory)
            proof_path = directory_path / "proof.jws"
            proof_path.write_text("header.payload.signature\n", encoding="utf-8")
            proof_path.chmod(0o600)
            self.assertEqual(load_jws(str(proof_path)), "header.payload.signature")

            proof_path.chmod(0o644)
            with self.assertRaises(ValueError):
                load_jws(str(proof_path))

            proof_path.chmod(0o600)
            link_path = directory_path / "proof-link.jws"
            link_path.symlink_to(proof_path)
            with self.assertRaises(OSError):
                load_jws(str(link_path))

            proof_path.write_bytes(b"\xff.\xff.\xff")
            with self.assertRaises(ProofRejectedError):
                load_jws(str(proof_path))

    def test_interactive_jws_input_fails_if_terminal_echo_cannot_be_disabled(self):
        with patch.object(sys.stdin, "isatty", return_value=True), patch(
            "redeem_question_credit.getpass.getpass",
            side_effect=getpass.GetPassWarning("no terminal control"),
        ):
            with self.assertRaises(VerificationUnavailableError):
                load_jws("-")

    def test_normalizes_uuid_and_hashes_without_storing_raw_value(self):
        raw = "01234567-89AB-CDEF-0123-456789ABCDEF"
        key = bytes(range(32))
        self.assertEqual(
            normalized_uuid(raw),
            "01234567-89ab-cdef-0123-456789abcdef",
        )
        self.assertNotIn(raw, digest(raw, key))
        self.assertNotEqual(digest(raw, key), digest(raw, b"x" * 32))

    def test_redeems_each_transaction_only_once(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / "redemptions.sqlite3"
            key = b"operator-test-key-material-32bytes"

            self.assertTrue(
                redeem_once(
                    ledger,
                    "987654321",
                    "submission-one",
                    "Production",
                    key,
                )
            )
            self.assertFalse(
                redeem_once(
                    ledger,
                    "987654321",
                    "submission-one",
                    "Production",
                    key,
                )
            )
            self.assertTrue(
                redeem_once(
                    ledger,
                    "987654322",
                    "submission-two",
                    "Production",
                    key,
                )
            )

            with sqlite3.connect(ledger) as connection:
                rows = connection.execute(
                    "SELECT transaction_hash, submission_hash FROM redemptions"
                ).fetchall()

            self.assertEqual(len(rows), 2)
            self.assertNotIn("987654321", repr(rows))
            self.assertNotIn("submission-one", repr(rows))

    def test_ledger_pins_schema_environment_and_key_without_reading_database(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / "redemptions.sqlite3"
            key = b"operator-test-key-material-32bytes"

            self.assertTrue(
                redeem_once(
                    ledger,
                    "1001",
                    "submission-one",
                    "Production",
                    key,
                )
            )

            with patch.object(
                Path,
                "read_bytes",
                side_effect=AssertionError("ledger bytes must not be read"),
            ):
                self.assertTrue(
                    redeem_once(
                        ledger,
                        "1002",
                        "submission-two",
                        "Production",
                        key,
                    )
                )

            with sqlite3.connect(ledger) as connection:
                metadata = connection.execute(
                    """
                    SELECT schema_version, environment, hmac_key_fingerprint
                    FROM ledger_metadata
                    """
                ).fetchall()

            self.assertEqual(
                metadata,
                [
                    (
                        LEDGER_SCHEMA_VERSION,
                        "Production",
                        ledger_key_fingerprint(key),
                    )
                ],
            )
            self.assertNotIn(repr(key), repr(metadata))

            with self.assertRaises(VerificationUnavailableError):
                redeem_once(
                    ledger,
                    "1003",
                    "submission-three",
                    "Sandbox",
                    key,
                )
            with self.assertRaises(VerificationUnavailableError):
                redeem_once(
                    ledger,
                    "1003",
                    "submission-three",
                    "Production",
                    b"different-operator-key-material-32bytes",
                )

            with sqlite3.connect(ledger) as connection:
                connection.execute(
                    "UPDATE ledger_metadata SET schema_version = 999"
                )
                connection.commit()
            with self.assertRaises(VerificationUnavailableError):
                redeem_once(
                    ledger,
                    "1003",
                    "submission-three",
                    "Production",
                    key,
                )

    def test_populated_legacy_ledger_requires_explicit_reconciliation(self):
        with tempfile.TemporaryDirectory() as directory:
            ledger = Path(directory) / "legacy.sqlite3"
            with sqlite3.connect(ledger) as connection:
                connection.execute(
                    """
                    CREATE TABLE redemptions (
                        transaction_hash TEXT PRIMARY KEY,
                        submission_hash TEXT NOT NULL,
                        environment TEXT NOT NULL,
                        redeemed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    )
                    """
                )
                connection.execute(
                    """
                    INSERT INTO redemptions (
                        transaction_hash,
                        submission_hash,
                        environment
                    ) VALUES ('old-transaction', 'old-submission', 'Production')
                    """
                )
                connection.commit()
            ledger.chmod(0o600)

            with self.assertRaises(VerificationUnavailableError):
                redeem_once(
                    ledger,
                    "1001",
                    "submission-one",
                    "Production",
                    b"operator-test-key-material-32bytes",
                )

    def test_sandbox_success_output_cannot_be_mistaken_for_paid_acceptance(self):
        self.assertTrue(accepted_message("Production").startswith("ACCEPTED:"))
        sandbox_message = accepted_message("Sandbox")
        self.assertTrue(sandbox_message.startswith("TEST-ONLY SANDBOX VERIFIED:"))
        self.assertNotIn("ACCEPTED", sandbox_message)
        self.assertIn("not a paid submission", sandbox_message)


class SignedProofVerificationTests(unittest.TestCase):
    def test_preflight_rejects_each_wrong_signed_field(self):
        cases = {
            "transaction identifier": {"transactionId": "not-a-number"},
            "product identifier": {"productId": "com.example.wrong"},
            "app-account token": {"appAccountToken": None},
            "product type": {"type": "NON_CONSUMABLE"},
            "quantity": {"quantity": 2},
            "revocation": {"revocationDate": 1_700_000_000_000},
        }
        for name, overrides in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(ProofRejectedError):
                    preflight_emailed_payload(
                        self.payload(**overrides),
                        "CONSUMABLE",
                    )

    def test_uses_signed_identifiers_and_separate_archived_and_current_verifiers(self):
        token = "01234567-89ab-cdef-0123-456789abcdef"
        emailed_payload = self.payload(
            transactionId="987654321",
            appAccountToken=token,
        )
        current_payload = self.payload(
            transactionId="987654321",
            appAccountToken=token,
        )
        verifier_modes = []
        api_queries = []

        class FakeVerifier:
            def __init__(
                self,
                roots,
                enable_online_checks,
                environment,
                bundle_id,
                app_apple_id,
            ):
                self.enable_online_checks = enable_online_checks
                verifier_modes.append(enable_online_checks)

            def verify_and_decode_signed_transaction(self, value):
                return current_payload if self.enable_online_checks else emailed_payload

        class FakeAPIClient:
            def __init__(self, *arguments):
                pass

            def get_transaction_info(self, transaction_id):
                api_queries.append(transaction_id)
                return SimpleNamespace(
                    signedTransactionInfo="current.header.payload.signature"
                )

        with tempfile.TemporaryDirectory() as directory:
            arguments = self.arguments(Path(directory))
            payload, submission_reference = verify_with_dependencies(
                arguments,
                api_client_class=FakeAPIClient,
                api_exception_class=FakeAPIException,
                environment_class=FakeEnvironment,
                consumable_type="CONSUMABLE",
                verifier_class=FakeVerifier,
                verification_exception_class=FakeVerificationException,
            )

        self.assertIs(payload, current_payload)
        self.assertEqual(submission_reference, token)
        self.assertEqual(verifier_modes, [False, True])
        self.assertEqual(api_queries, [emailed_payload.transactionId])
        self.assertFalse(hasattr(arguments, "transaction_id"))
        self.assertFalse(hasattr(arguments, "submission_reference"))

    def test_rejects_wrong_signed_product_before_constructing_api_client(self):
        emailed_payload = self.payload(productId="com.example.wrong")
        api_client_was_constructed = False

        class FakeVerifier:
            def __init__(self, *arguments):
                self.enable_online_checks = arguments[1]

            def verify_and_decode_signed_transaction(self, value):
                return emailed_payload

        class FakeAPIClient:
            def __init__(self, *arguments):
                nonlocal api_client_was_constructed
                api_client_was_constructed = True

        with tempfile.TemporaryDirectory() as directory:
            arguments = self.arguments(Path(directory))
            with self.assertRaises(ProofRejectedError):
                verify_with_dependencies(
                    arguments,
                    api_client_class=FakeAPIClient,
                    api_exception_class=FakeAPIException,
                    environment_class=FakeEnvironment,
                    consumable_type="CONSUMABLE",
                    verifier_class=FakeVerifier,
                    verification_exception_class=FakeVerificationException,
                )

        self.assertFalse(api_client_was_constructed)

    def test_verifier_factory_uses_signed_date_then_online_current_validation(self):
        modes = []

        class CapturingVerifier:
            def __init__(self, roots, online, environment, bundle_id, app_apple_id):
                modes.append(online)

        make_verifiers(
            CapturingVerifier,
            [b"root"],
            FakeEnvironment.PRODUCTION,
            123456789,
        )
        self.assertEqual(modes, [False, True])

    @staticmethod
    def payload(**overrides):
        values = {
            "transactionId": "123456789",
            "productId": PRODUCT_ID,
            "appAccountToken": "01234567-89ab-cdef-0123-456789abcdef",
            "type": "CONSUMABLE",
            "quantity": 1,
            "revocationDate": None,
        }
        values.update(overrides)
        return SimpleNamespace(**values)

    @staticmethod
    def arguments(directory: Path):
        root = directory / "AppleRootCA.cer"
        root.write_bytes(b"test-root")
        private_key = directory / "AuthKey_TEST.p8"
        private_key.write_bytes(b"test-private-key")
        private_key.chmod(0o600)
        jws_file = directory / "proof.jws"
        jws_file.write_text("header.payload.signature", encoding="utf-8")
        jws_file.chmod(0o600)
        return SimpleNamespace(
            environment="Production",
            allow_test_environment=False,
            app_apple_id=123456789,
            key_id="KEY123",
            issuer_id="01234567-89ab-cdef-0123-456789abcdef",
            root_certificate=[root],
            private_key=private_key,
            jws_file=str(jws_file),
        )


class FakeEnvironment:
    PRODUCTION = "Production"
    SANDBOX = "Sandbox"


class FakeAPIException(Exception):
    pass


class FakeVerificationException(Exception):
    pass


if __name__ == "__main__":
    unittest.main()
