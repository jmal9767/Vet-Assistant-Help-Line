#!/usr/bin/env python3
"""Verify and atomically redeem one Apple-signed question credit.

This operator-only tool stores hashes, not customer email or question content.
It must run before an incoming message is accepted as a new paid submission.
"""

from __future__ import annotations

import argparse
import getpass
import hashlib
import hmac
import os
from pathlib import Path
import sqlite3
import stat
import sys
import warnings
from typing import List, Optional, Tuple
from uuid import UUID

BUNDLE_ID = "com.bayareaapps.vetassistanthelpline"
PRODUCT_ID = "com.bayareaapps.vetassistanthelpline.education_question"
MAX_JWS_BYTES = 32 * 1024
MAX_PRIVATE_FILE_BYTES = 1024 * 1024
LEDGER_SCHEMA_VERSION = 1
LEDGER_KEY_FINGERPRINT_CONTEXT = (
    b"com.bayareaapps.vetassistanthelpline/redemption-ledger-key/v1"
)


class ProofRejectedError(Exception):
    """The customer-supplied proof definitively failed validation."""


class VerificationUnavailableError(Exception):
    """No verdict is safe because operator or Apple infrastructure failed."""


class OperationalArgumentParser(argparse.ArgumentParser):
    """Treat operator invocation errors as unavailable, never rejected proof."""

    def error(self, message: str) -> None:
        raise VerificationUnavailableError(f"Invalid operator arguments: {message}")


def parse_args() -> argparse.Namespace:
    parser = OperationalArgumentParser(
        description="Verify an Apple-signed transaction and redeem it once."
    )
    parser.add_argument(
        "--jws-file",
        default="-",
        help="Path to compact JWS, or '-' (default) to read it from standard input.",
    )
    parser.add_argument("--ledger", required=True, type=Path)
    parser.add_argument(
        "--ledger-key-file",
        required=True,
        type=Path,
        help="Operator-only file containing at least 32 random bytes for HMAC.",
    )
    parser.add_argument("--private-key", required=True, type=Path)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument(
        "--root-certificate",
        required=True,
        action="append",
        type=Path,
        help="Apple root certificate in DER format; repeat for each current root.",
    )
    parser.add_argument(
        "--environment",
        choices=("Production", "Sandbox"),
        default="Production",
    )
    parser.add_argument(
        "--app-apple-id",
        type=int,
        help="Numeric App Store app ID; required for Production verification.",
    )
    parser.add_argument(
        "--allow-test-environment",
        action="store_true",
        help="Permit Sandbox verification. Never use its ledger for production mail.",
    )
    return parser.parse_args()


def normalized_uuid(value: str) -> str:
    return str(UUID(value)).lower()


def digest(value: str, ledger_key: bytes) -> str:
    return hmac.new(
        ledger_key,
        value.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def ledger_key_fingerprint(ledger_key: bytes) -> str:
    return hmac.new(
        ledger_key,
        LEDGER_KEY_FINGERPRINT_CONTEXT,
        hashlib.sha256,
    ).hexdigest()


def accepted_message(environment: str) -> str:
    if environment == "Sandbox":
        return (
            "TEST-ONLY SANDBOX VERIFIED: transaction recorded only in the "
            "Sandbox ledger; this is not a paid submission."
        )
    return "ACCEPTED: Apple proof verified and transaction atomically redeemed once."


def require_private_regular_file(path: Path, label: str) -> None:
    file_status = path.lstat()
    if not stat.S_ISREG(file_status.st_mode):
        raise ValueError(f"{label} must be a regular file, not a link or device")
    if os.name == "posix" and file_status.st_mode & 0o077:
        raise ValueError(f"{label} must not be readable by group or other users")


def read_bounded_regular_file(
    path: Path,
    label: str,
    *,
    maximum_bytes: int,
    require_private_permissions: bool,
) -> bytes:
    flags = os.O_RDONLY
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    try:
        file_status = os.fstat(descriptor)
        if not stat.S_ISREG(file_status.st_mode):
            raise ValueError(f"{label} must be a regular file, not a link or device")
        if (
            require_private_permissions
            and os.name == "posix"
            and file_status.st_mode & 0o077
        ):
            raise ValueError(
                f"{label} must not be readable by group or other users"
            )
        value = os.read(descriptor, maximum_bytes + 1)
        if len(value) > maximum_bytes:
            raise ValueError(f"{label} exceeds {maximum_bytes} bytes")
        return value
    finally:
        os.close(descriptor)


def require_private_file(
    path: Path,
    label: str,
    maximum_bytes: int = MAX_PRIVATE_FILE_BYTES,
) -> bytes:
    return read_bounded_regular_file(
        path,
        label,
        maximum_bytes=maximum_bytes,
        require_private_permissions=True,
    )


def load_jws(source: str) -> str:
    if source == "-":
        if sys.stdin.isatty():
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter("error", getpass.GetPassWarning)
                    raw = getpass.getpass("Paste the compact JWS (input hidden): ")
            except getpass.GetPassWarning as error:
                raise VerificationUnavailableError(
                    "Terminal echo could not be disabled; use an approved private JWS file"
                ) from error
        else:
            raw = sys.stdin.read(MAX_JWS_BYTES + 1)
        if len(raw.encode("utf-8")) > MAX_JWS_BYTES:
            raise ProofRejectedError("JWS input exceeds 32 KiB")
    else:
        raw_bytes = require_private_file(
            Path(source),
            "Temporary JWS file",
            maximum_bytes=MAX_JWS_BYTES,
        )
        try:
            raw = raw_bytes.decode("utf-8")
        except UnicodeDecodeError as error:
            raise ProofRejectedError("JWS input must be UTF-8 text") from error

    value = "".join(raw.split())
    if value.count(".") != 2:
        raise ProofRejectedError(
            "JWS input must contain one compact signed transaction"
        )
    return value


def make_api_client(
    client_class,
    private_key_path: Path,
    key_id: str,
    issuer_id: str,
    bundle_id: str,
    environment,
):
    """Construct Apple's client without converting the PEM key away from bytes."""
    private_key = require_private_file(
        private_key_path,
        "App Store private key",
    )
    return client_class(
        private_key,
        key_id,
        issuer_id,
        bundle_id,
        environment,
    )


def make_verifiers(
    verifier_class,
    roots: List[bytes],
    environment,
    app_apple_id: Optional[int],
):
    """Build historical-proof and current-state verifiers with distinct clocks."""
    archived_proof_verifier = verifier_class(
        roots,
        False,
        environment,
        BUNDLE_ID,
        app_apple_id,
    )
    current_state_verifier = verifier_class(
        roots,
        True,
        environment,
        BUNDLE_ID,
        app_apple_id,
    )
    return archived_proof_verifier, current_state_verifier


def require_transaction_id(value, label: str) -> str:
    if (
        not isinstance(value, str)
        or not value.isascii()
        or not value.isdecimal()
        or not 1 <= len(value) <= 32
    ):
        raise ProofRejectedError(f"{label} must contain 1 to 32 ASCII digits")
    return value


def preflight_emailed_payload(payload, consumable_type) -> Tuple[str, str]:
    """Derive trusted identifiers and reject wrong signed product data early."""
    transaction_id = require_transaction_id(
        payload.transactionId,
        "Signed transaction identifier",
    )
    try:
        submission_reference = normalized_uuid(payload.appAccountToken)
    except (AttributeError, TypeError, ValueError) as error:
        raise ProofRejectedError(
            "Signed transaction is missing a valid app-account token"
        ) from error

    checks = {
        "product identifier": (payload.productId, PRODUCT_ID),
        "product type": (payload.type, consumable_type),
        "quantity": (payload.quantity, 1),
        "revocation": (payload.revocationDate, None),
    }
    mismatches = [
        name for name, (actual, expected) in checks.items() if actual != expected
    ]
    if mismatches:
        raise ProofRejectedError(
            "Emailed transaction proof mismatch: " + ", ".join(mismatches)
        )

    return transaction_id, submission_reference


def handle_verification_exception(error, *, apple_current_data: bool) -> None:
    status_name = getattr(getattr(error, "status", None), "name", "")
    if apple_current_data or status_name == "RETRYABLE_VERIFICATION_FAILURE":
        raise VerificationUnavailableError(
            "Apple verification is temporarily unavailable; hold this message and retry"
        ) from error
    raise ProofRejectedError("Apple-signed transaction proof is invalid") from error


def verify_with_dependencies(
    args: argparse.Namespace,
    *,
    api_client_class,
    api_exception_class,
    environment_class,
    consumable_type,
    verifier_class,
    verification_exception_class,
):
    """Verify with injectable Apple types so the production path is testable."""
    if args.environment != "Production" and not args.allow_test_environment:
        raise VerificationUnavailableError(
            "Sandbox redemption requires --allow-test-environment"
        )
    if args.environment == "Production" and args.app_apple_id is None:
        raise VerificationUnavailableError(
            "--app-apple-id is required for Production"
        )
    if args.app_apple_id is not None and args.app_apple_id <= 0:
        raise VerificationUnavailableError(
            "--app-apple-id must be a positive integer"
        )
    if (
        not args.key_id.isascii()
        or not args.key_id.isalnum()
        or not 1 <= len(args.key_id) <= 64
    ):
        raise VerificationUnavailableError(
            "--key-id must contain 1 to 64 ASCII letters or digits"
        )
    try:
        issuer_id = str(UUID(args.issuer_id))
    except ValueError as error:
        raise VerificationUnavailableError(
            "--issuer-id must be a UUID"
        ) from error

    environment = (
        environment_class.PRODUCTION
        if args.environment == "Production"
        else environment_class.SANDBOX
    )
    roots = [
        read_bounded_regular_file(
            path,
            "Apple root certificate",
            maximum_bytes=MAX_PRIVATE_FILE_BYTES,
            require_private_permissions=False,
        )
        for path in args.root_certificate
    ]
    archived_verifier, current_verifier = make_verifiers(
        verifier_class,
        roots,
        environment,
        args.app_apple_id,
    )
    try:
        emailed_payload = archived_verifier.verify_and_decode_signed_transaction(
            load_jws(args.jws_file)
        )
    except verification_exception_class as error:
        handle_verification_exception(error, apple_current_data=False)

    transaction_id, expected_token = preflight_emailed_payload(
        emailed_payload,
        consumable_type,
    )

    api_client = make_api_client(
        api_client_class,
        args.private_key,
        args.key_id,
        issuer_id,
        BUNDLE_ID,
        environment,
    )
    try:
        current_info = api_client.get_transaction_info(transaction_id)
    except api_exception_class as error:
        raise VerificationUnavailableError(
            "Apple's current-transaction lookup is unavailable; hold and retry"
        ) from error
    if not current_info.signedTransactionInfo:
        raise VerificationUnavailableError(
            "Apple returned no current signed transaction information"
        )
    try:
        payload = current_verifier.verify_and_decode_signed_transaction(
            current_info.signedTransactionInfo
        )
    except verification_exception_class as error:
        handle_verification_exception(error, apple_current_data=True)

    try:
        actual_token = normalized_uuid(payload.appAccountToken)
    except (AttributeError, TypeError, ValueError) as error:
        raise ProofRejectedError(
            "Apple's current transaction is missing a valid app-account token"
        ) from error
    checks = {
        "transaction identifier": (payload.transactionId, transaction_id),
        "product identifier": (payload.productId, PRODUCT_ID),
        "app-account token": (actual_token, expected_token),
        "product type": (payload.type, consumable_type),
        "quantity": (payload.quantity, 1),
        "revocation": (payload.revocationDate, None),
    }
    mismatches = [
        name for name, (actual, expected) in checks.items() if actual != expected
    ]
    if mismatches:
        raise ProofRejectedError(
            "Current transaction proof mismatch: " + ", ".join(mismatches)
        )

    return payload, expected_token


def verify(args: argparse.Namespace):
    try:
        from appstoreserverlibrary.api_client import (
            APIException,
            AppStoreServerAPIClient,
        )
        from appstoreserverlibrary.models.Environment import Environment
        from appstoreserverlibrary.models.Type import Type
        from appstoreserverlibrary.signed_data_verifier import (
            SignedDataVerifier,
            VerificationException,
        )
    except ImportError as error:
        raise VerificationUnavailableError(
            "Install operator/requirements.lock with hash checking in an isolated environment first"
        ) from error
    return verify_with_dependencies(
        args,
        api_client_class=AppStoreServerAPIClient,
        api_exception_class=APIException,
        environment_class=Environment,
        consumable_type=Type.CONSUMABLE,
        verifier_class=SignedDataVerifier,
        verification_exception_class=VerificationException,
    )


def redeem_once(
    ledger_path: Path,
    transaction_id: str,
    submission_reference: str,
    environment: str,
    ledger_key: bytes,
) -> bool:
    if environment not in {"Production", "Sandbox"}:
        raise VerificationUnavailableError("Unsupported redemption environment")
    if len(ledger_key) < 32:
        raise VerificationUnavailableError(
            "Ledger HMAC key must contain at least 32 random bytes"
        )

    repository_root = Path(__file__).resolve().parent.parent
    try:
        ledger_path.resolve().relative_to(repository_root)
    except ValueError:
        pass
    else:
        raise ValueError("Redemption ledger must be stored outside the repository")

    previous_umask = os.umask(0o077) if os.name == "posix" else None
    try:
        ledger_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if os.name == "posix" and ledger_path.parent.stat().st_mode & 0o077:
            raise VerificationUnavailableError(
                "Redemption ledger directory must not be accessible by group "
                "or other users"
            )
        if ledger_path.is_symlink():
            raise VerificationUnavailableError(
                "Redemption ledger must not be a symbolic link"
            )
        if ledger_path.exists():
            require_private_regular_file(ledger_path, "Redemption ledger")
        else:
            flags = os.O_CREAT | os.O_EXCL | os.O_WRONLY
            if hasattr(os, "O_NOFOLLOW"):
                flags |= os.O_NOFOLLOW
            descriptor = os.open(ledger_path, flags, 0o600)
            os.close(descriptor)

        connection = sqlite3.connect(ledger_path)
        if os.name == "posix":
            os.chmod(ledger_path, 0o600)
        try:
            connection.execute("BEGIN IMMEDIATE")
            try:
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS ledger_metadata (
                        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                        schema_version INTEGER NOT NULL,
                        environment TEXT NOT NULL,
                        hmac_key_fingerprint TEXT NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS redemptions (
                        transaction_hash TEXT PRIMARY KEY,
                        submission_hash TEXT NOT NULL,
                        environment TEXT NOT NULL,
                        redeemed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    )
                    """
                )

                expected_metadata = (
                    LEDGER_SCHEMA_VERSION,
                    environment,
                    ledger_key_fingerprint(ledger_key),
                )
                metadata_rows = connection.execute(
                    """
                    SELECT schema_version, environment, hmac_key_fingerprint
                    FROM ledger_metadata
                    ORDER BY singleton
                    """
                ).fetchall()
                if not metadata_rows:
                    redemption_count = connection.execute(
                        "SELECT COUNT(*) FROM redemptions"
                    ).fetchone()[0]
                    if redemption_count:
                        raise VerificationUnavailableError(
                            "Populated legacy ledger has no pinned metadata; "
                            "stop and reconcile it before migration"
                        )
                    connection.execute(
                        """
                        INSERT INTO ledger_metadata (
                            singleton,
                            schema_version,
                            environment,
                            hmac_key_fingerprint
                        ) VALUES (1, ?, ?, ?)
                        """,
                        expected_metadata,
                    )
                else:
                    if len(metadata_rows) != 1:
                        raise VerificationUnavailableError(
                            "Ledger metadata must contain exactly one pinned row"
                        )
                    stored_schema, stored_environment, stored_fingerprint = (
                        metadata_rows[0]
                    )
                    metadata_matches = (
                        stored_schema == LEDGER_SCHEMA_VERSION
                        and stored_environment == environment
                        and isinstance(stored_fingerprint, str)
                        and hmac.compare_digest(
                            stored_fingerprint,
                            expected_metadata[2],
                        )
                    )
                    if not metadata_matches:
                        raise VerificationUnavailableError(
                            "Ledger schema, environment, or HMAC key does not "
                            "match its pinned metadata"
                        )

                transaction_hash = digest(transaction_id, ledger_key)
                try:
                    connection.execute(
                        """
                        INSERT INTO redemptions (
                            transaction_hash,
                            submission_hash,
                            environment
                        ) VALUES (?, ?, ?)
                        """,
                        (
                            transaction_hash,
                            digest(submission_reference, ledger_key),
                            environment,
                        ),
                    )
                except sqlite3.IntegrityError:
                    already_redeemed = connection.execute(
                        "SELECT 1 FROM redemptions WHERE transaction_hash = ?",
                        (transaction_hash,),
                    ).fetchone()
                    if already_redeemed:
                        connection.rollback()
                        return False
                    raise
            except Exception:
                connection.rollback()
                raise
            else:
                connection.commit()
                return True
        finally:
            connection.close()
    finally:
        if previous_umask is not None:
            os.umask(previous_umask)


def main() -> int:
    try:
        args = parse_args()
        ledger_key = require_private_file(args.ledger_key_file, "Ledger HMAC key")
        if len(ledger_key) < 32:
            raise ValueError("Ledger HMAC key must contain at least 32 random bytes")
        payload, submission_reference = verify(args)
        accepted = redeem_once(
            args.ledger,
            str(payload.transactionId),
            submission_reference,
            args.environment,
            ledger_key,
        )
    except ProofRejectedError as error:
        print(f"REJECTED: {error}", file=sys.stderr)
        return 2
    except Exception as error:
        print(
            f"UNAVAILABLE: {error}. No payment verdict was recorded; hold and retry.",
            file=sys.stderr,
        )
        return 4

    if not accepted:
        print(
            "REPLAYED: this verified transaction was already redeemed; "
            "do not accept it as a new paid question.",
            file=sys.stderr,
        )
        return 3

    print(accepted_message(args.environment))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
