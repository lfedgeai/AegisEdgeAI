"""
Configuration management for the OpenTelemetry microservice architecture.
Uses Pydantic settings for type-safe configuration with environment variable support.
"""

from typing import Optional
from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings with environment variable support."""
    
    # Service configuration
    service_name: str = Field(default="opentelemetry-service", env="SERVICE_NAME")
    service_version: str = Field(default="1.0.0", env="SERVICE_VERSION")
    debug: bool = Field(default=False, env="DEBUG")
    
    # Server configuration
    host: str = Field(default="0.0.0.0", env="HOST")
    port: int = Field(default=5000, env="PORT")
    
    # Agent port allocation (for multi-agent support)
    agent_base_port: int = Field(default=8401, env="AGENT_BASE_PORT")
    agent_port_offset: int = Field(default=0, env="AGENT_PORT_OFFSET")
    
    # Agent TPM handle allocation (for multi-agent support)
    agent_base_app_handle: str = Field(default="0x8101000B", env="AGENT_BASE_APP_HANDLE")
    
    # TLS/SSL configuration
    ssl_enabled: bool = Field(default=True, env="SSL_ENABLED")
    ssl_cert_path: Optional[str] = Field(default=None, env="SSL_CERT_PATH")
    ssl_key_path: Optional[str] = Field(default=None, env="SSL_KEY_PATH")
    
    # TPM2 configuration
    tpm2_device: str = Field(default="/dev/tpm0", env="TPM2_DEVICE")
    tpm2_app_ctx_path: str = Field(default="tpm/app.ctx", env="TPM2_APP_CTX_PATH")
    tpm2_primary_ctx_path: str = Field(default="tpm/primary.ctx", env="TPM2_PRIMARY_CTX_PATH")
    tpm2_ak_ctx_path: str = Field(default="tpm/ak.ctx", env="TPM2_AK_CTX_PATH")
    use_swtpm: bool = Field(default=True, env="USE_SWTPM")
    
    # Public key configuration (for collector verification)
    public_key_path: str = Field(default="tpm/appsk_pubkey.pem", env="PUBLIC_KEY_PATH")
    verify_script_path: str = Field(default="tpm/verify_app_message_signature.sh", env="VERIFY_SCRIPT_PATH")
    
    # Software TPM (swtpm) configuration
    swtpm_dir: str = Field(default="$HOME/.swtpm/ztpm", env="SWTPM_DIR")
    swtpm_port: int = Field(default=2321, env="SWTPM_PORT")
    swtpm_ctrl: int = Field(default=2322, env="SWTPM_CTRL")
    tpm2tools_tcti: str = Field(default="swtpm:host=127.0.0.1,port=2321", env="TPM2TOOLS_TCTI")
    ek_handle: str = Field(default="0x81010001", env="EK_HANDLE")
    ak_handle: str = Field(default="0x8101000A", env="AK_HANDLE")
    app_handle: str = Field(default="0x8101000B", env="APP_HANDLE")
    
    # OpenTelemetry configuration
    otel_endpoint: str = Field(default="http://localhost:4317", env="OTEL_ENDPOINT")
    otel_service_name: str = Field(default="opentelemetry-service", env="OTEL_SERVICE_NAME")
    otel_log_level: str = Field(default="INFO", env="OTEL_LOG_LEVEL")
    
    # API Gateway configuration
    gateway_host: str = Field(default="localhost", env="GATEWAY_HOST")
    gateway_port: int = Field(default=9000, env="GATEWAY_PORT")
    gateway_ssl_verify: bool = Field(default=False, env="GATEWAY_SSL_VERIFY")
    
    # Collector configuration
    collector_host: str = Field(default="localhost", env="COLLECTOR_HOST")
    collector_port: int = Field(default=8500, env="COLLECTOR_PORT")
    collector_ssl_verify: bool = Field(default=False, env="COLLECTOR_SSL_VERIFY")
    
    # Security configuration
    nonce_length: int = Field(default=32, env="NONCE_LENGTH")
    signature_algorithm: str = Field(default="sha256", env="SIGNATURE_ALGORITHM")
    
    # Geographic region configuration
    geographic_region: str = Field(default="US", env="GEOGRAPHIC_REGION")
    geographic_state: str = Field(default="California", env="GEOGRAPHIC_STATE")
    geographic_city: str = Field(default="Santa Clara", env="GEOGRAPHIC_CITY")
    
    # Geographic policy configuration (for collector)
    allowed_regions: list = Field(default=["US"], env="ALLOWED_REGIONS")
    allowed_states: list = Field(default=["California", "Texas", "New York"], env="ALLOWED_STATES")
    allowed_cities: list = Field(default=["Santa Clara", "San Francisco", "Austin", "New York"], env="ALLOWED_CITIES")
    
    # Logging configuration
    log_level: str = Field(default="INFO", env="LOG_LEVEL")
    log_format: str = Field(default="json", env="LOG_FORMAT")

    # Compliance Agent configuration
    compliance_agent_host: str = Field(default="0.0.0.0", env="COMPLIANCE_AGENT_HOST")
    compliance_agent_port: int = Field(default=5001, env="COMPLIANCE_AGENT_PORT")
    llm_model_path: Optional[str] = Field(default="models/mistral-7b-instruct-v0.1.Q4_K_M.gguf", env="LLM_MODEL_PATH")
    
    class Config:
        env_file = ".env"
        case_sensitive = False


# Global settings instance
settings = Settings()
