#!/usr/bin/env python3
"""
Unified-Identity - Verification: Hardware Integration & Delegated Certification

Unit tests for Delegated Certification Client
"""

import base64
import json
import os
import socket
import tempfile
import unittest
from unittest.mock import patch

from delegated_certification import DelegatedCertificationClient, is_unified_identity_enabled


# Unified-Identity - Verification: Hardware Integration & Delegated Certification
class TestDelegatedCertificationClient(unittest.TestCase):
    """Test cases for Delegated Certification Client"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "true"
        self.socket_path = "/tmp/test-keylime-certify.sock"
    
    def tearDown(self):
        """Clean up test fixtures"""
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        if "UNIFIED_IDENTITY_ENABLED" in os.environ:
            del os.environ["UNIFIED_IDENTITY_ENABLED"]
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
    
    def test_feature_flag_check(self):
        """Test feature flag check"""
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "true"
        self.assertTrue(is_unified_identity_enabled())
        
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "false"
        self.assertFalse(is_unified_identity_enabled())
    
    @patch.object(DelegatedCertificationClient, "_perform_http_request")
    def test_request_certificate_success(self, mock_http_request):
        """Test successful certificate request"""
        response = {
            "result": "SUCCESS",
            "app_key_certificate": base64.b64encode(b"test-certificate").decode("utf-8"),
            "agent_uuid": "1234-uuid",
        }
        mock_http_request.return_value = json.dumps(response)
        
        client = DelegatedCertificationClient(endpoint=f"unix://{self.socket_path}")
        
        # Create temporary context file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, agent_uuid, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path,
                challenge_nonce="test-nonce"
            )
            
            self.assertTrue(success)
            self.assertIsNotNone(cert_b64)
            self.assertEqual(agent_uuid, "1234-uuid")
            self.assertIsNone(error)
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)
    
    @patch.object(DelegatedCertificationClient, "_perform_http_request")
    def test_request_certificate_error(self, mock_http_request):
        """Test certificate request with error response"""
        response = {
            "result": "ERROR",
            "error": "Test error message",
        }
        mock_http_request.return_value = json.dumps(response)
        
        client = DelegatedCertificationClient(endpoint=f"unix://{self.socket_path}")
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, agent_uuid, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path,
                challenge_nonce="test-nonce"
            )
            
            self.assertFalse(success)
            self.assertIsNone(cert_b64)
            self.assertIsNone(agent_uuid)
            self.assertIsNotNone(error)
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)
    
    def test_request_certificate_socket_not_found(self):
        """Test certificate request when socket doesn't exist"""
        # Unified-Identity - Verification: Hardware Integration & Delegated Certification
        client = DelegatedCertificationClient(endpoint="unix:///nonexistent/socket")
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, agent_uuid, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path,
                challenge_nonce="test-nonce"
            )
            
            self.assertFalse(success)
            self.assertIsNone(cert_b64)
            self.assertIsNone(agent_uuid)
            self.assertIsNotNone(error)
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)


# Unified-Identity - Verification: Hardware Integration & Delegated Certification
if __name__ == "__main__":
    unittest.main()

