#!/usr/bin/env python3
"""
Agent startup script that loads agent-specific configuration.

Usage:
    python start_agent.py <agent_name>
    
Example:
    python start_agent.py agent-001
    python start_agent.py agent-002
"""

import os
import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any
import structlog

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from config import settings

# Configure logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    wrapper_class=structlog.stdlib.BoundLogger,
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger(__name__)


class AgentConfig:
    """Agent configuration loader."""
    
    def __init__(self, agent_name: str):
        """
        Initialize agent configuration.
        
        Args:
            agent_name: Name of the agent (e.g., 'agent-001')
        """
        self.agent_name = agent_name
        self.config_path = f"agents/{agent_name}/config.json"
        self.config = self._load_config()
    
    def _load_config(self) -> Dict[str, Any]:
        """Load agent configuration from JSON file."""
        if not os.path.exists(self.config_path):
            raise FileNotFoundError(f"Agent config not found: {self.config_path}")
        
        try:
            with open(self.config_path, 'r') as f:
                config = json.load(f)
            
            # Validate required fields
            required_fields = ['agent_name', 'tpm_public_key', 'tpm_context_file']
            for field in required_fields:
                if field not in config:
                    raise ValueError(f"Missing required field in config: {field}")
            
            logger.info("Agent configuration loaded successfully", 
                       agent_name=self.agent_name,
                       config_path=self.config_path)
            
            return config
            
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in config file: {e}")
    
    def _calculate_agent_port(self) -> int:
        """Calculate agent-specific port based on agent name."""
        try:
            # Extract agent number from agent name (e.g., "agent-001" -> 1)
            agent_number = int(self.agent_name.split('-')[-1])
            
            # Calculate port: base_port + agent_number - 1
            # agent-001 -> port 8401, agent-002 -> port 8402, etc.
            agent_port = settings.agent_base_port + agent_number - 1
            
            logger.info("Calculated agent port", 
                       agent_name=self.agent_name,
                       agent_number=agent_number,
                       base_port=settings.agent_base_port,
                       calculated_port=agent_port)
            
            return agent_port
            
        except (ValueError, IndexError):
            # Fallback to base port if agent name doesn't follow pattern
            logger.warning("Could not parse agent number from name, using base port", 
                          agent_name=self.agent_name,
                          base_port=settings.agent_base_port)
            return settings.agent_base_port
    
    def _calculate_agent_app_handle(self) -> str:
        """Calculate agent-specific APP_HANDLE based on agent name."""
        try:
            # Extract agent number from agent name (e.g., "agent-001" -> 1)
            agent_number = int(self.agent_name.split('-')[-1])
            
            # Parse base handle (e.g., "0x8101000B" -> 0x8101000B)
            base_handle = int(settings.agent_base_app_handle, 16)
            
            # Calculate handle: base_handle + agent_number - 1
            # agent-001 -> 0x8101000B, agent-002 -> 0x8101000C, etc.
            agent_handle = base_handle + agent_number - 1
            
            # Convert back to hex string
            agent_handle_hex = f"0x{agent_handle:08X}"
            
            logger.info("Calculated agent APP_HANDLE", 
                       agent_name=self.agent_name,
                       agent_number=agent_number,
                       base_handle=settings.agent_base_app_handle,
                       calculated_handle=agent_handle_hex)
            
            return agent_handle_hex
            
        except (ValueError, IndexError):
            # Fallback to base handle if agent name doesn't follow pattern
            logger.warning("Could not parse agent number from name, using base handle", 
                          agent_name=self.agent_name,
                          base_handle=settings.agent_base_app_handle)
            return settings.agent_base_app_handle
    
    def get_env_vars(self) -> Dict[str, str]:
        """Get environment variables for the agent."""
        # Calculate agent-specific port and APP_HANDLE
        agent_port = self._calculate_agent_port()
        agent_app_handle = self._calculate_agent_app_handle()
        
        env_vars = {
            "SERVICE_NAME": f"opentelemetry-agent-{self.agent_name}",
            "PORT": str(agent_port),
            "COLLECTOR_HOST": settings.gateway_host,  # Agent should connect to gateway
            "COLLECTOR_PORT": str(settings.gateway_port),  # Agent should connect to gateway
            "GATEWAY_HOST": settings.gateway_host,
            "GATEWAY_PORT": str(settings.gateway_port),
            "OTEL_ENDPOINT": settings.otel_endpoint,
            "LOG_LEVEL": "INFO",
            # Agent-specific configuration
            "AGENT_NAME": self.config['agent_name'],
            "TPM2_APP_CTX_PATH": self.config['tpm_context_file'],
            # Note: We no longer need PUBLIC_KEY_PATH since the agent reads from config
            # Agent-specific TPM handle
            "APP_HANDLE": agent_app_handle,
            # Note: Geographic region is now loaded from agent config at runtime
            # Environment variables can override if needed:
            # GEOGRAPHIC_REGION, GEOGRAPHIC_STATE, GEOGRAPHIC_CITY
        }
        
        return env_vars


def start_agent(agent_name: str):
    """Start an agent with the specified configuration."""
    try:
        # Load agent configuration
        agent_config = AgentConfig(agent_name)
        
        # Set environment variables
        env_vars = agent_config.get_env_vars()
        for key, value in env_vars.items():
            os.environ[key] = value
        
        logger.info("Starting agent", 
                   agent_name=agent_name,
                   config_path=agent_config.config_path,
                   env_vars=env_vars)
        
        # Import and start the agent app
        from agent.app import app
        
        # Start the Flask app
        app.run(
            host=settings.host,
            port=int(env_vars['PORT']),
            debug=settings.debug,
            ssl_context='adhoc' if settings.ssl_enabled else None
        )
        
    except Exception as e:
        logger.error("Failed to start agent", 
                    agent_name=agent_name,
                    error=str(e))
        sys.exit(1)


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Start an OpenTelemetry agent with specific configuration')
    parser.add_argument('agent_name', help='Name of the agent (e.g., agent-001)')
    
    args = parser.parse_args()
    
    print(f"🚀 Starting agent: {args.agent_name}")
    print(f"📁 Config file: agents/{args.agent_name}/config.json")
    
    # Calculate and display port and APP_HANDLE
    agent_config = AgentConfig(args.agent_name)
    agent_port = agent_config._calculate_agent_port()
    agent_app_handle = agent_config._calculate_agent_app_handle()
    print(f"🌐 Agent port: {agent_port}")
    print(f"🔐 APP_HANDLE: {agent_app_handle}")
    print(f"🔗 Gateway: {settings.gateway_host}:{settings.gateway_port}")
    print(f"📊 Collector: {settings.collector_host}:{settings.collector_port}")
    
    start_agent(args.agent_name)


if __name__ == "__main__":
    main()
