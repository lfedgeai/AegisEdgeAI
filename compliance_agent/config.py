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

    # LLM configuration for the rule auditor tool
    llm_model_path: Optional[str] = Field(
        default="models/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
        env="LLM_MODEL_PATH"
    )

    class Config:
        env_file = ".env"
        case_sensitive = False

# Global settings instance
settings = Settings()