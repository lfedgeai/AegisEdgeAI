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

    # LLM configuration for the multi-model rule auditor tool
    llm_models: list = Field(
        default=[
            {
                "name": "Mistral-7B-Instruct-v0.1",
                "path": "models/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
                "url": "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf"
            },
            {
                "name": "OpenHermes-2.5-Mistral-7B",
                "path": "models/openhermes-2.5-mistral-7b.Q4_K_M.gguf",
                "url": "https://huggingface.co/TheBloke/OpenHermes-2.5-Mistral-7B-GGUF/resolve/main/openhermes-2.5-mistral-7b.Q4_K_M.gguf"
            },
            {
                "name": "Zephyr-7B-beta",
                "path": "models/zephyr-7b-beta.Q4_K_M.gguf",
                "url": "https://huggingface.co/TheBloke/zephyr-7B-beta-GGUF/resolve/main/zephyr-7b-beta.Q4_K_M.gguf"
            }
        ],
        env="LLM_MODELS"
    )

    class Config:
        env_file = ".env"
        case_sensitive = False

# Global settings instance
settings = Settings()