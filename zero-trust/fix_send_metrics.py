#!/usr/bin/env python3
"""
Fix send_metrics method to remove signing logic
"""

# Read the file
with open('agent/app.py', 'r') as f:
    lines = f.readlines()

# Find the start and end of send_metrics method
start_line = None
end_line = None

for i, line in enumerate(lines):
    if 'def send_metrics(' in line and start_line is None:
        start_line = i
    elif start_line is not None and line.strip() and not line.startswith(' ') and not line.startswith('\t'):
        end_line = i
        break

if start_line is None:
    print("❌ Could not find send_metrics method")
    exit(1)

print(f"Found send_metrics method: lines {start_line + 1} to {end_line}")

# New send_metrics method (simplified, no signing)
new_method = '''    def send_metrics(self, payload: Dict[str, Any], custom_headers: Dict[str, str] = None) -> tuple[bool, str]:
        """
        Send signed metrics payload to the OpenTelemetry Collector.
        
        Args:
            payload: Signed metrics payload (already contains payload signature)
            custom_headers: Pre-signed headers for the request (including Workload-Geo-ID and Signature)
            
        Returns:
            Tuple of (success: bool, error_message: str)
        """
        with tracer.start_as_current_span("send_metrics"):
            try:
                agent_name = payload.get("agent_name", os.environ.get("AGENT_NAME", settings.service_name))
                
                # Use custom headers if provided, otherwise create basic headers
                if custom_headers:
                    metrics_headers = custom_headers.copy()
                    # Ensure Content-Type is set
                    metrics_headers["Content-Type"] = "application/json"
                else:
                    # Fallback to basic headers (for backward compatibility)
                    metrics_headers = {
                        "Content-Type": "application/json",
                    }
                
                logger.info("🔍 [AGENT] Sending metrics with headers",
                           agent_name=agent_name,
                           has_workload_geo_id=bool(metrics_headers.get("Workload-Geo-ID")),
                           has_signature=bool(metrics_headers.get("Signature")),
                           has_signature_input=bool(metrics_headers.get("Signature-Input")))

                response = self.session.post(
                    f"{self.base_url}/metrics",
                    json=payload,
                    headers=metrics_headers,
                )
                response.raise_for_status()
                
                logger.info("✅ [AGENT] Metrics sent successfully to collector", 
                           response_status=response.status_code,
                           response_size=len(response.content))
                return True, "", None
                
            except requests.exceptions.HTTPError as e:
                # Handle HTTP errors with detailed error messages
                error_details = "Unknown error"
                rejected_by = "unknown"
                validation_type = "unknown"
                try:
                    error_response = e.response.json()
                    if "error" in error_response:
                        error_details = error_response["error"]
                        if "details" in error_response:
                            error_details += f" - {error_response['details']}"
                    if "rejected_by" in error_response:
                        rejected_by = error_response["rejected_by"]
                    if "validation_type" in error_response:
                        validation_type = error_response["validation_type"]
                except:
                    error_details = e.response.text if e.response.text else str(e)
                
                logger.error("❌ [AGENT] HTTP error from gateway", 
                           status_code=e.response.status_code,
                           error_details=error_details,
                           rejected_by=rejected_by,
                           validation_type=validation_type,
                           response_text=e.response.text[:200] if e.response.text else "No response text")
                error_counter.add(1, {"operation": "send_metrics", "error": error_details})
                
                # Return enhanced error response if available
                try:
                    error_response = e.response.json()
                    return False, error_details, error_response
                except:
                    return False, error_details, None
                
            except Exception as e:
                logger.error("Failed to send metrics to gateway", error=str(e))
                error_counter.add(1, {"operation": "send_metrics", "error": str(e)})
                return False, str(e), None

'''

# Replace the method
new_lines = lines[:start_line] + [new_method] + lines[end_line:]

# Write the file
with open('agent/app.py', 'w') as f:
    f.writelines(new_lines)

print("✅ Fixed send_metrics method - removed signing logic")
