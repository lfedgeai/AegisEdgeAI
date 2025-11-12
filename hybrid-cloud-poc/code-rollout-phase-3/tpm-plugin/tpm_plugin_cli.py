#!/usr/bin/env python3
"""
Unified-Identity - Phase 3: Hardware Integration & Delegated Certification

CLI wrapper for TPM Plugin
This script provides a command-line interface for the TPM plugin,
allowing it to be called from SPIRE Agent (Go code).
"""

import argparse
import json
import logging
import sys
from pathlib import Path

from tpm_plugin import TPMPlugin, is_unified_identity_enabled
from delegated_certification import DelegatedCertificationClient

# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
# Configure logging to stderr so JSON output on stdout is clean
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    stream=sys.stderr  # Send logs to stderr, not stdout
)
logger = logging.getLogger(__name__)


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def cmd_generate_app_key(args):
    """Generate App Key command"""
    if not is_unified_identity_enabled():
        logger.error("Unified-Identity - Phase 3: Feature flag disabled")
        sys.exit(1)
    
    plugin = TPMPlugin(work_dir=args.work_dir)
    success, app_key_public, app_key_ctx = plugin.generate_app_key(force=args.force)
    
    if not success:
        logger.error("Unified-Identity - Phase 3: Failed to generate App Key")
        sys.exit(1)
    
    # Output JSON
    result = {
        "app_key_public": app_key_public,
        "app_key_context": app_key_ctx,
        "status": "success"
    }
    print(json.dumps(result))
    sys.exit(0)


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def cmd_generate_quote(args):
    """Generate TPM Quote command"""
    if not is_unified_identity_enabled():
        logger.error("Unified-Identity - Phase 3: Feature flag disabled")
        sys.exit(1)
    
    if not args.nonce:
        logger.error("Unified-Identity - Phase 3: Nonce is required (use --nonce)")
        sys.exit(1)
    
    plugin = TPMPlugin(work_dir=args.work_dir)
    success, quote_b64, metadata = plugin.generate_quote(
        nonce=args.nonce,
        pcr_list=args.pcr_list or "sha256:0,1"
    )
    
    if not success:
        logger.error("Unified-Identity - Phase 3: Failed to generate quote")
        sys.exit(1)
    
    # Output base64 quote
    print(quote_b64)
    sys.exit(0)


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def cmd_request_certificate(args):
    """Request App Key certificate command"""
    if not is_unified_identity_enabled():
        logger.error("Unified-Identity - Phase 3: Feature flag disabled")
        sys.exit(1)
    
    if not args.app_key_public or not args.app_key_context:
        logger.error("Unified-Identity - Phase 3: App key public and context are required")
        sys.exit(1)
    
    # Unified-Identity - Phase 3: Support both --endpoint and --socket-path (for backward compatibility)
    endpoint = args.endpoint
    if endpoint is None and args.socket_path:
        # Legacy: convert socket path to endpoint format
        endpoint = f"unix://{args.socket_path}"
    
    client = DelegatedCertificationClient(endpoint=endpoint)
    success, cert_b64, error = client.request_certificate(
        app_key_public=args.app_key_public,
        app_key_context_path=args.app_key_context
    )
    
    if not success:
        logger.error("Unified-Identity - Phase 3: Failed to request certificate: %s", error)
        sys.exit(1)
    
    # Output base64 certificate
    print(cert_b64)
    sys.exit(0)


# Unified-Identity - Phase 3: Hardware Integration & Delegated Certification
def main():
    """Main CLI entry point"""
    parser = argparse.ArgumentParser(
        description="Unified-Identity - Phase 3: TPM Plugin CLI"
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")
    
    # Generate App Key command
    parser_generate = subparsers.add_parser("generate-app-key", help="Generate App Key")
    parser_generate.add_argument("--work-dir", type=str, help="Working directory")
    parser_generate.add_argument("--force", action="store_true", help="Force regeneration")
    parser_generate.set_defaults(func=cmd_generate_app_key)
    
    # Generate Quote command
    parser_quote = subparsers.add_parser("generate-quote", help="Generate TPM Quote")
    parser_quote.add_argument("--work-dir", type=str, help="Working directory")
    parser_quote.add_argument("--nonce", type=str, help="Challenge nonce")
    parser_quote.add_argument("--pcr-list", type=str, default="sha256:0,1", help="PCR selection")
    parser_quote.add_argument("--app-key-context", type=str, help="App Key context path")
    parser_quote.set_defaults(func=cmd_generate_quote)
    
    # Request Certificate command
    parser_cert = subparsers.add_parser("request-certificate", help="Request App Key certificate")
    parser_cert.add_argument("--app-key-public", type=str, required=True, help="App Key public key (PEM)")
    parser_cert.add_argument("--app-key-context", type=str, required=True, help="App Key context path")
    parser_cert.add_argument("--endpoint", type=str, 
                            default=None,
                            help="rust-keylime Agent endpoint (HTTP or UNIX socket). Defaults to http://localhost:9002/v2.2/delegated_certification/certify_app_key")
    parser_cert.add_argument("--socket-path", type=str, 
                            default=None,
                            help="[Deprecated] Use --endpoint instead. Keylime Agent socket path")
    parser_cert.set_defaults(func=cmd_request_certificate)
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    args.func(args)


if __name__ == "__main__":
    main()

