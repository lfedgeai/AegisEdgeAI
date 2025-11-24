"""
Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)

Unit tests for fact provider (geolocation).
"""

import unittest
from unittest.mock import MagicMock, patch

from keylime import fact_provider


class TestFactProvider(unittest.TestCase):
    """Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)"""

    def setUp(self):
        """Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)"""
        # Clear fact store
        fact_provider._fact_store.clear()

    def test_get_host_identifier_from_ek(self):
        """Unified-Identity: Test host identifier generation from EK"""
        tpm_ek = "test_ek_public_key_data"
        host_id = fact_provider.get_host_identifier_from_ek(tpm_ek)

        self.assertIsNotNone(host_id)
        self.assertTrue(host_id.startswith("ek-"))
        self.assertEqual(len(host_id), 19)  # "ek-" (3) + 16 hex chars = 19

    def test_get_host_identifier_from_ek_none(self):
        """Unified-Identity: Test host identifier with None EK"""
        host_id = fact_provider.get_host_identifier_from_ek(None)
        self.assertIsNone(host_id)

    def test_get_host_identifier_from_ak(self):
        """Unified-Identity: Test host identifier generation from AK"""
        tpm_ak = "test_ak_public_key_data"
        host_id = fact_provider.get_host_identifier_from_ak(tpm_ak)

        self.assertIsNotNone(host_id)
        self.assertTrue(host_id.startswith("ak-"))
        self.assertEqual(len(host_id), 19)  # "ak-" (3) + 16 hex chars = 19

    def test_get_host_identifier_from_ak_none(self):
        """Unified-Identity: Test host identifier with None AK"""
        host_id = fact_provider.get_host_identifier_from_ak(None)
        self.assertIsNone(host_id)

    def test_get_attested_claims_empty(self):
        """Unified-Identity: Test getting empty attested claims when no facts available"""
                claims = fact_provider.get_attested_claims()

        self.assertIsInstance(claims, dict)
        # Should be empty when no facts are available
        self.assertEqual(len(claims), 0)

    def test_set_and_get_facts_from_store(self):
        """Unified-Identity: Test setting and getting facts from store"""
        host_id = "ek-test1234567890"
        facts = {
            "geolocation": {"type": "mobile", "sensor_id": "12d1:1433", "value": ""},
        }

        fact_provider.set_facts_in_store(host_id, facts)
        retrieved = fact_provider._get_facts_from_store(host_id)

        self.assertIsNotNone(retrieved)
        self.assertEqual(retrieved, facts)

    def test_get_facts_from_store_not_found(self):
        """Unified-Identity: Test getting facts for non-existent host"""
        host_id = "ek-nonexistent"
        facts = fact_provider._get_facts_from_store(host_id)

        self.assertIsNone(facts)

    def test_get_attested_claims_from_store(self):
        """Unified-Identity: Test getting attested claims from fact store"""
        # Set up fact store
        host_id = "ek-test1234567890"
        stored_facts = {
            "geolocation": {"type": "gnss", "sensor_id": "gps-001", "value": "N52.5200, E13.4050"},
        }
        fact_provider.set_facts_in_store(host_id, stored_facts)

        # Get facts using EK that generates the same host_id
        # We need to use the same EK value that generates "ek-test1234567890"
        # For this test, we'll directly test the store lookup
        tpm_ek = "test_ek_for_host_id"  # This will generate a different hash, so we'll use direct lookup
        # Instead, let's test with the known host_id by mocking get_host_identifier_from_ek
        with patch("keylime.fact_provider.get_host_identifier_from_ek", return_value=host_id):
            claims = fact_provider.get_attested_claims(tpm_ek=tpm_ek)

        # Should retrieve facts from store
        self.assertIsInstance(claims, dict)
        self.assertIn("geolocation", claims)
        self.assertEqual(claims["geolocation"], stored_facts["geolocation"])


if __name__ == "__main__":
    unittest.main()

