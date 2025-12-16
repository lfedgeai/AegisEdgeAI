# Correct code for keylime/keylime/cloud_verifier_tornado.py
# Lines ~2142-2148
#
# This is what the code SHOULD look like (replace lines 2142-2146)

async def _make_request() -> Any:
    # Only pass ssl_context if using HTTPS
    request_kwargs = {'timeout': agent_quote_timeout}
    if use_https and ssl_context:
        request_kwargs['context'] = ssl_context
    return await tornado_requests.request('GET', quote_url, **request_kwargs)

# EXPLANATION:
# - Uses agent_quote_timeout variable (from config: agent_quote_timeout_seconds = 300)
# - Uses the properly configured ssl_context (with certificate validation)
# - Clean, readable code
# - Secure (validates certificates)
#
# If you get certificate errors, the fix is NOT to disable validation.
# The fix is to clean state and regenerate matching certificates:
#   rm -rf /tmp/keylime-agent /tmp/spire-* /opt/spire/data/* keylime/cv_ca keylime/*.db
#   ./test_complete_control_plane.sh --no-pause
#   ./test_complete.sh --no-pause
