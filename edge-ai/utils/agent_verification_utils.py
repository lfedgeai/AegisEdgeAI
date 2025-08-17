"""
Agent Verification Utilities

This module provides agent verification capabilities using the new agent-specific allowlist format.
"""

import os
import json
import structlog
import logging
from typing import Dict, Any, Optional, List
from pathlib import Path

# Set log level to DEBUG
logging.basicConfig(level=logging.DEBUG)

logger = structlog.get_logger(__name__)


class AgentVerificationError(Exception):
    """Custom exception for agent verification errors."""
    pass


class AgentVerificationUtils:
    """
    Utility class for agent verification using agent-specific allowlists.
    
    This class loads allowed agents from a JSON file and verifies agent information
    including agent name, TPM public key, and geolocation.
    """
    
    def __init__(self, allowed_agents_path: str = "collector/allowed_agents.json"):
        """
        Initialize AgentVerificationUtils.
        
        Args:
            allowed_agents_path: Path to the allowed agents JSON file
        """
        # Resolve the path relative to the project root
        if not os.path.isabs(allowed_agents_path):
            # Get the directory where this script is located
            script_dir = os.path.dirname(os.path.abspath(__file__))
            # Go up one level to the project root
            project_root = os.path.dirname(script_dir)
            # Construct the full path
            self.allowed_agents_path = os.path.join(project_root, allowed_agents_path)
        else:
            self.allowed_agents_path = allowed_agents_path
            
        self.allowed_agents = self._load_allowed_agents()
        
        logger.info("AgentVerificationUtils initialized", 
                   allowed_agents_path=os.path.abspath(self.allowed_agents_path),
                   agent_count=len(self.allowed_agents))
    
    def _load_allowed_agents(self) -> List[Dict[str, Any]]:
        """
        Load allowed agents from JSON file.
        
        Returns:
            List of allowed agent configurations
            
        Raises:
            AgentVerificationError: If file cannot be loaded or parsed
        """
        try:
            logger.debug("Loading allowed agents", file_path=self.allowed_agents_path)
            
            if not os.path.exists(self.allowed_agents_path):
                raise AgentVerificationError(f"Allowed agents file not found: {self.allowed_agents_path}")
            
            with open(self.allowed_agents_path, 'r') as f:
                content = f.read()
                logger.debug("File content loaded", content_length=len(content))
                agents = json.loads(content)
            
            logger.debug("JSON parsed successfully", agents_type=type(agents), agents_length=len(agents) if isinstance(agents, list) else "not a list")
            
            if not isinstance(agents, list):
                raise AgentVerificationError("Allowed agents file must contain a JSON array")
            
            # Validate each agent configuration
            for i, agent in enumerate(agents):
                self._validate_agent_config(agent, i)
            
            logger.info("Allowed agents loaded successfully", 
                       agent_count=len(agents),
                       agent_names=[agent.get('agent_name') for agent in agents])
            
            return agents
            
        except json.JSONDecodeError as e:
            logger.error("JSON decode error", error=str(e), file_path=self.allowed_agents_path)
            raise AgentVerificationError(f"Invalid JSON in allowed agents file: {e}")
        except Exception as e:
            logger.error("Failed to load allowed agents", error=str(e), file_path=self.allowed_agents_path)
            raise AgentVerificationError(f"Failed to load allowed agents: {e}")
    
    def _validate_agent_config(self, agent: Dict[str, Any], index: int) -> None:
        """
        Validate an individual agent configuration.
        
        Args:
            agent: Agent configuration dictionary
            index: Index of the agent in the list
            
        Raises:
            AgentVerificationError: If agent configuration is invalid
        """
        required_fields = ['agent_name', 'tpm_public_key', 'geolocation']
        for field in required_fields:
            if field not in agent:
                raise AgentVerificationError(f"Agent {index}: Missing required field '{field}'")
        
        # Validate geolocation
        geolocation = agent.get('geolocation', {})
        if not isinstance(geolocation, dict):
            raise AgentVerificationError(f"Agent {index}: geolocation must be an object")
        
        required_geo_fields = ['country', 'state', 'city']
        for field in required_geo_fields:
            if field not in geolocation:
                raise AgentVerificationError(f"Agent {index}: Missing required geolocation field '{field}'")
    
    def verify_agent(self, payload: Dict[str, Any]) -> bool:
        """
        Verify agent information from the payload.
        
        Args:
            payload: Metrics payload containing agent information
            
        Returns:
            True if agent is verified, False otherwise
        """
        try:
            # Extract agent information from payload
            agent_name = payload.get('agent_name')
            tpm_public_key = payload.get('tpm_public_key')  # Now contains raw public key content
            geolocation = payload.get('geolocation', {})
            
            if not agent_name:
                logger.warning("No agent name in payload")
                return False
            
            if not tpm_public_key:
                logger.warning("No TPM public key in payload")
                return False
            
            if not geolocation:
                logger.warning("No geolocation in payload")
                return False
            
            # Find the agent in allowed agents
            agent_config = self._find_agent_by_name(agent_name)
            if not agent_config:
                logger.warning("Agent not found in allowlist", agent_name=agent_name)
                return False
            
            # Verify TPM public key content
            if not self._verify_tpm_public_key(agent_config, tpm_public_key):
                logger.warning("TPM public key verification failed", 
                             agent_name=agent_name,
                             received_key_length=len(tpm_public_key))
                return False
            
            # Verify geolocation
            if not self._verify_geolocation(agent_config, geolocation):
                logger.warning("Geolocation verification failed", 
                             agent_name=agent_name,
                             expected_geo=agent_config.get('geolocation'),
                             received_geo=geolocation)
                return False
            
            logger.info("Agent verification successful", 
                       agent_name=agent_name,
                       geolocation=geolocation)
            
            return True
            
        except Exception as e:
            logger.error("Agent verification failed", error=str(e))
            return False
    
    def _find_agent_by_name(self, agent_name: str) -> Optional[Dict[str, Any]]:
        """
        Find agent configuration by name.
        
        Args:
            agent_name: Name of the agent to find
            
        Returns:
            Agent configuration if found, None otherwise
        """
        for agent in self.allowed_agents:
            if agent.get('agent_name') == agent_name:
                return agent
        return None
    
    def _verify_tpm_public_key(self, agent_config: Dict[str, Any], received_public_key: str) -> bool:
        """
        Verify TPM public key content matches the expected public key.
        
        Args:
            agent_config: Agent configuration from allowlist
            received_public_key: TPM public key content from payload
            
        Returns:
            True if public keys match, False otherwise
        """
        try:
            # Get the expected public key content from allowlist
            expected_public_key = agent_config.get('tpm_public_key')
            if not expected_public_key:
                logger.warning("No public key content in agent config")
                return False
            
            # Verify that the received public key matches the expected one
            if received_public_key != expected_public_key:
                logger.warning("Public key content mismatch", 
                             agent_name=agent_config.get('agent_name'),
                             expected_length=len(expected_public_key),
                             received_length=len(received_public_key))
                return False
            
            logger.info("TPM public key verification successful", 
                       agent_name=agent_config.get('agent_name'))
            
            return True
            
        except Exception as e:
            logger.error("TPM public key verification failed", error=str(e))
            return False
    
    def _verify_geolocation(self, agent_config: Dict[str, Any], received_geo: Dict[str, Any]) -> bool:
        """
        Verify geolocation matches the expected location.
        
        Args:
            agent_config: Agent configuration from allowlist
            received_geo: Geolocation from payload
            
        Returns:
            True if geolocation matches, False otherwise
        """
        expected_geo = agent_config.get('geolocation', {})
        
        # Check country
        if expected_geo.get('country') != received_geo.get('country'):
            return False
        
        # Check state
        if expected_geo.get('state') != received_geo.get('state'):
            return False
        
        # Check city
        if expected_geo.get('city') != received_geo.get('city'):
            return False
        
        return True
    
    def get_agent_info(self, agent_name: str) -> Optional[Dict[str, Any]]:
        """
        Get agent information by name.
        
        Args:
            agent_name: Name of the agent
            
        Returns:
            Agent information if found, None otherwise
        """
        return self._find_agent_by_name(agent_name)
    
    def list_allowed_agents(self) -> List[str]:
        """
        Get list of all allowed agent names.
        
        Returns:
            List of allowed agent names
        """
        return [agent.get('agent_name') for agent in self.allowed_agents if agent.get('agent_name')]
    
    def reload_allowed_agents(self) -> None:
        """
        Reload allowed agents from the configuration file.
        """
        self.allowed_agents = self._load_allowed_agents()
        logger.info("Allowed agents reloaded", agent_count=len(self.allowed_agents))
