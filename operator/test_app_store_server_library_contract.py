"""Smoke-test the installed Apple library surface used by the operator tool."""

from importlib.metadata import version
import inspect
from pathlib import Path
import re
import unittest

from appstoreserverlibrary.api_client import (
    APIException,
    AppStoreServerAPIClient,
)
from appstoreserverlibrary.models.Environment import Environment
from appstoreserverlibrary.models.JWSTransactionDecodedPayload import (
    JWSTransactionDecodedPayload,
)
from appstoreserverlibrary.models.TransactionInfoResponse import (
    TransactionInfoResponse,
)
from appstoreserverlibrary.models.Type import Type
from appstoreserverlibrary.signed_data_verifier import (
    SignedDataVerifier,
    VerificationException,
)


class AppStoreServerLibraryContractTests(unittest.TestCase):
    """Detect dependency updates that break the production verification path."""

    def test_installed_version_matches_exact_requirement(self):
        requirement = (
            Path(__file__).with_name("requirements.txt").read_text(encoding="utf-8")
        )
        match = re.fullmatch(
            r"app-store-server-library==([^\s]+)\s*",
            requirement,
        )
        self.assertIsNotNone(match, "Apple library must use one exact version pin")
        self.assertEqual(version("app-store-server-library"), match.group(1))

    def test_client_and_verifier_accept_the_arguments_used_by_operator(self):
        inspect.signature(AppStoreServerAPIClient).bind(
            b"private-key-bytes",
            "KEY123",
            "01234567-89ab-cdef-0123-456789abcdef",
            "com.bayareaapps.vetassistanthelpline",
            Environment.PRODUCTION,
        )
        inspect.signature(AppStoreServerAPIClient.get_transaction_info).bind(
            object(),
            "123456789",
        )
        inspect.signature(SignedDataVerifier).bind(
            [b"root-certificate-bytes"],
            True,
            Environment.PRODUCTION,
            "com.bayareaapps.vetassistanthelpline",
            123456789,
        )
        inspect.signature(
            SignedDataVerifier.verify_and_decode_signed_transaction
        ).bind(object(), "header.payload.signature")

    def test_response_models_expose_every_consumed_signed_field(self):
        token = "01234567-89ab-cdef-0123-456789abcdef"
        response = TransactionInfoResponse(
            signedTransactionInfo="header.payload.signature"
        )
        payload = JWSTransactionDecodedPayload(
            transactionId="123456789",
            productId=(
                "com.bayareaapps.vetassistanthelpline.education_question"
            ),
            appAccountToken=token,
            type=Type.CONSUMABLE,
            quantity=1,
            revocationDate=None,
        )

        self.assertEqual(
            response.signedTransactionInfo,
            "header.payload.signature",
        )
        self.assertEqual(payload.transactionId, "123456789")
        self.assertEqual(
            payload.productId,
            "com.bayareaapps.vetassistanthelpline.education_question",
        )
        self.assertEqual(payload.appAccountToken, token)
        self.assertEqual(payload.type, Type.CONSUMABLE)
        self.assertEqual(payload.quantity, 1)
        self.assertIsNone(payload.revocationDate)

    def test_operator_catches_library_exception_types(self):
        self.assertTrue(issubclass(APIException, Exception))
        self.assertTrue(issubclass(VerificationException, Exception))


if __name__ == "__main__":
    unittest.main()
