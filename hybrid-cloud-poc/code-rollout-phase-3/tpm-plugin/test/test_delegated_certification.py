#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

Unit tests for Delegated Certification Client
"""

import base64
import json
import os
import socket
import tempfile
import unittest
from unittest.mock import Mock, patch, MagicMock

from delegated_certification import DelegatedCertificationClient, is_unified_identity_enabled


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
class TestDelegatedCertificationClient(unittest.TestCase):
    """Test cases for Delegated Certification Client"""
    
    def setUp(self):
        """Set up test fixtures"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "true"
        self.socket_path = "/tmp/test-keylime-certify.sock"
    
    def tearDown(self):
        """Clean up test fixtures"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        if "UNIFIED_IDENTITY_ENABLED" in os.environ:
            del os.environ["UNIFIED_IDENTITY_ENABLED"]
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
    
    def test_feature_flag_check(self):
        """Test feature flag check"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "true"
        self.assertTrue(is_unified_identity_enabled())
        
        os.environ["UNIFIED_IDENTITY_ENABLED"] = "false"
        self.assertFalse(is_unified_identity_enabled())
    
    @patch('socket.socket')
    def test_request_certificate_success(self, mock_socket_class):
        """Test successful certificate request"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        # Mock socket
        mock_sock = MagicMock()
        mock_socket_class.return_value = mock_sock
        
        # Mock successful HTTP/1.1 response over UDS
        response = {
            "result": "SUCCESS",
            "app_key_certificate": base64.b64encode(b"test-certificate").decode('utf-8')
        }
        response_json = json.dumps(response)
        response_bytes = response_json.encode('utf-8')
        
        # HTTP/1.1 response format
        http_response = (
            f"HTTP/1.1 200 OK\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(response_bytes)}\r\n"
            f"\r\n"
        ).encode('utf-8') + response_bytes
        
        # Setup mock recv to return HTTP response in chunks
        mock_sock.recv.side_effect = [
            http_response,  # Return full response in first call
            b''  # Empty on subsequent calls
        ]
        
        client = DelegatedCertificationClient(endpoint=f"unix://{self.socket_path}")
        
        # Create temporary context file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path
            )
            
            # Verify socket was used correctly
            self.assertTrue(mock_sock.connect.called)
            self.assertTrue(mock_sock.sendall.called)
            self.assertTrue(mock_sock.recv.called)
            self.assertTrue(mock_sock.close.called)
            
            # Verify success
            self.assertTrue(success)
            self.assertIsNotNone(cert_b64)
            self.assertIsNone(error)
            
            # Validate JSON payload uses correct field name
            # The sendall is called with HTTP request, extract JSON body
            sendall_calls = [call[0][0] for call in mock_sock.sendall.call_args_list]
            # Find the call that contains JSON (should be the HTTP request body)
            for call_data in sendall_calls:
                if isinstance(call_data, bytes):
                    # Look for JSON in the HTTP request body
                    try:
                        # HTTP request format: "POST ... HTTP/1.1\r\n...\r\n\r\n{json}"
                        if b'\r\n\r\n' in call_data:
                            body_start = call_data.find(b'\r\n\r\n') + 4
                            body = call_data[body_start:]
                            payload = json.loads(body.decode('utf-8'))
                            self.assertIn("app_key_context_path", payload)
                            self.assertNotIn("app_ctx", payload)
                            break
                    except (ValueError, json.JSONDecodeError):
                        continue
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)
    
    @patch('socket.socket')
    def test_request_certificate_error(self, mock_socket_class):
        """Test certificate request with error response"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        mock_sock = MagicMock()
        mock_socket_class.return_value = mock_sock
        
        # Mock error HTTP/1.1 response over UDS
        response = {
            "result": "ERROR",
            "error": "Test error message"
        }
        response_json = json.dumps(response)
        response_bytes = response_json.encode('utf-8')
        
        # HTTP/1.1 response format
        http_response = (
            f"HTTP/1.1 200 OK\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(response_bytes)}\r\n"
            f"\r\n"
        ).encode('utf-8') + response_bytes
        
        # Setup mock recv to return HTTP response
        mock_sock.recv.side_effect = [
            http_response,  # Return full response in first call
            b''  # Empty on subsequent calls
        ]
        
        client = DelegatedCertificationClient(endpoint=f"unix://{self.socket_path}")
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path
            )
            
            self.assertFalse(success)
            self.assertIsNone(cert_b64)
            self.assertIsNotNone(error)
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)
    
    def test_request_certificate_socket_not_found(self):
        """Test certificate request when socket doesn't exist"""
        # Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
        client = DelegatedCertificationClient(endpoint="unix:///nonexistent/socket")
        
        with tempfile.NamedTemporaryFile(delete=False, suffix='.ctx') as f:
            f.write(b"test context data")
            ctx_path = f.name
        
        try:
            success, cert_b64, error = client.request_certificate(
                app_key_public="-----BEGIN PUBLIC KEY-----\nTEST\n-----END PUBLIC KEY-----",
                app_key_context_path=ctx_path
            )
            
            self.assertFalse(success)
            self.assertIsNone(cert_b64)
            self.assertIsNotNone(error)
        finally:
            if os.path.exists(ctx_path):
                os.remove(ctx_path)


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
if __name__ == "__main__":
    unittest.main()

