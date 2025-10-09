"""
Configuration management for the AI Compliance Agent.
Uses Pydantic for type-safe configuration with environment variable support.
"""

from typing import Optional
from pydantic import Field
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    """Application settings with environment variable support."""

    # Service configuration
    service_name: str = Field(default="compliance-agent", env="SERVICE_NAME")
    debug: bool = Field(default=False, env="DEBUG")

    # Server configuration
    host: str = Field(default="0.0.0.0", env="HOST")
    port: int = Field(default=5001, env="PORT")

    # LLM configuration
    # The path is relative to the `compliance_agent` directory.
    llm_model_path: Optional[str] = Field(
        default="models/Phi-3-mini-4k-instruct-q4.gguf",
        env="LLM_MODEL_PATH"
    )

    class Config:
        env_file = ".env"
        case_sensitive = False

# Global settings instance
settings = Settings()