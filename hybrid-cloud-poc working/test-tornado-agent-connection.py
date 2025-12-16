#!/usr/bin/env python3
"""
Test tornado HTTP client connection to rust-keylime agent
This replicates the exact connection method used by Keylime Verifier
"""

import asyncio
import sys
import ssl
from concurrent.futures import ThreadPoolExecutor
from typing import Any

# Add keylime to path
sys.path.insert(0, 'keylime')

from keylime import tornado_requests, web_util, config

def test_agent_connection(agent_ip: str = "127.0.0.1", agent_port: int = 9002, use_mtls: bool = True):
    """Test connection to rust-keylime agent using tornado HTTP client"""
    
    print(f"Testing connection to rust-keylime agent at {agent_ip}:{agent_port}")
    print(f"mTLS enabled: {use_mtls}")
    print("")
    
    # Test nonce
    nonce = "test-nonce-12345678"
    
    # Build SSL context if mTLS is enabled
    ssl_context = None
    if use_mtls:
        try:
            print("[1] Building mTLS SSL context...")
            # This replicates what the verifier does
            ssl_context = web_util.generate_agent_tls_context('verifier', None)
            print("✓ SSL context created successfully")
            print(f"  Protocol: {ssl_context.protocol}")
            print(f"  Check hostname: {ssl_context.check_hostname}")
            print(f"  Verify mode: {ssl_context.verify_mode}")
        except Exception as e:
            print(f"✗ Failed to build SSL context: {e}")
            print("  Falling back to HTTP")
            use_mtls = False
            ssl_context = None
    
    print("")
    
    # Try different API versions
    api_versions = ['2.4', '2.2', '1.0']
    timeout = 60
    
    for api_version in api_versions:
        protocol = 'https' if use_mtls else 'http'
        quote_url = f"{protocol}://{agent_ip}:{agent_port}/v{api_version}/quotes/identity?nonce={nonce}"
        
        print(f"[{api_version}] Testing API v{api_version}...")
        print(f"  URL: {quote_url}")
        
        async def _make_request() -> Any:
            request_kwargs = {'timeout': timeout}
            if use_mtls and ssl_context:
                request_kwargs['context'] = ssl_context
            return await tornado_requests.request('GET', quote_url, **request_kwargs)
        
        def _run_request():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                return loop.run_until_complete(_make_request())
            finally:
                loop.close()
        
        try:
            with ThreadPoolExecutor(max_workers=1) as executor:
                response = executor.submit(_run_request).result(timeout=timeout + 5)
            
            print(f"  ✓ Response received")
            print(f"    Status: {response.status_code}")
            if response.body:
                body_preview = response.body.decode('utf-8', errors='ignore')[:200]
                print(f"    Body preview: {body_preview}")
            
            if response.status_code == 200:
                print(f"  ✓ API v{api_version} works!")
                return True
            elif response.status_code == 404:
                print(f"  ℹ API v{api_version} not supported (404)")
            else:
                print(f"  ✗ API v{api_version} returned error: {response.status_code}")
        
        except Exception as exc:
            print(f"  ✗ Request failed: {exc}")
            print(f"    Exception type: {type(exc).__name__}")
            if hasattr(exc, 'code'):
                print(f"    Error code: {exc.code}")
        
        print("")
    
    return False

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Test tornado connection to rust-keylime agent')
    parser.add_argument('--ip', default='127.0.0.1', help='Agent IP address')
    parser.add_argument('--port', type=int, default=9002, help='Agent port')
    parser.add_argument('--no-mtls', action='store_true', help='Disable mTLS (use HTTP)')
    
    args = parser.parse_args()
    
    success = test_agent_connection(args.ip, args.port, not args.no_mtls)
    
    if success:
        print("✓ Connection test PASSED")
        sys.exit(0)
    else:
        print("✗ Connection test FAILED")
        print("")
        print("Troubleshooting:")
        print("1. Check if agent is running: ps aux | grep keylime_agent")
        print("2. Check if agent is listening: netstat -tln | grep 9002")
        print("3. Try without mTLS: python3 test-tornado-agent-connection.py --no-mtls")
        print("4. Check agent logs: tail -50 /tmp/rust-keylime-agent.log")
        print("5. Check verifier logs: tail -50 /tmp/keylime-verifier.log")
        sys.exit(1)
