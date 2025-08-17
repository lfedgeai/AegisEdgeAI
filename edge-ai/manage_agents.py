#!/usr/bin/env python3
"""
Agent Management Script

This script helps manage agent configurations and collector allowlists.

Usage:
    python manage_agents.py create <agent_name> <country> <state> <city>
    python manage_agents.py list
    python manage_agents.py info <agent_name>
    python manage_agents.py update-allowlist
"""

import os
import sys
import json
import argparse
from pathlib import Path
from typing import Dict, Any, List
import structlog

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


class AgentManager:
    """Agent configuration manager."""
    
    def __init__(self):
        self.agents_dir = Path("agents")
        self.allowlist_path = Path("collector/allowed_agents.json")
        self.agents_dir.mkdir(exist_ok=True)
    
    def create_agent(self, agent_name: str, country: str, state: str, city: str, description: str = None) -> bool:
        """
        Create a new agent configuration.
        
        Args:
            agent_name: Name of the agent
            country: Country code (e.g., US)
            state: State or province
            city: City name
            description: Optional description
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Create agent directory
            agent_dir = self.agents_dir / agent_name
            agent_dir.mkdir(exist_ok=True)
            
            # Create agent config
            config = {
                "agent_name": agent_name,
                "tpm_public_key_path": "tpm/appsk_pubkey.pem",
                "tpm_context_file": "tpm/app.ctx",
                "geolocation": {
                    "country": country,
                    "state": state,
                    "city": city
                },
                "description": description or f"Edge AI agent for {city}, {state}, {country}",
                "created_at": self._get_timestamp(),
                "status": "active"
            }
            
            config_path = agent_dir / "config.json"
            with open(config_path, 'w') as f:
                json.dump(config, f, indent=2)
            
            logger.info("Agent configuration created", 
                       agent_name=agent_name,
                       config_path=str(config_path))
            
            # Update allowlist
            self.update_allowlist()
            
            return True
            
        except Exception as e:
            logger.error("Failed to create agent", 
                        agent_name=agent_name,
                        error=str(e))
            return False
    
    def list_agents(self) -> List[str]:
        """
        List all configured agents.
        
        Returns:
            List of agent names
        """
        agents = []
        for agent_dir in self.agents_dir.iterdir():
            if agent_dir.is_dir():
                config_path = agent_dir / "config.json"
                if config_path.exists():
                    agents.append(agent_dir.name)
        return sorted(agents)
    
    def get_agent_info(self, agent_name: str) -> Dict[str, Any]:
        """
        Get agent configuration information.
        
        Args:
            agent_name: Name of the agent
            
        Returns:
            Agent configuration dictionary
        """
        config_path = self.agents_dir / agent_name / "config.json"
        if not config_path.exists():
            raise FileNotFoundError(f"Agent config not found: {config_path}")
        
        with open(config_path, 'r') as f:
            return json.load(f)
    
    def update_allowlist(self) -> bool:
        """
        Update the collector allowlist with all agent configurations.
        
        Returns:
            True if successful, False otherwise
        """
        try:
            allowlist = []
            
            for agent_name in self.list_agents():
                agent_info = self.get_agent_info(agent_name)
                
                allowlist_entry = {
                    "agent_name": agent_info["agent_name"],
                    "tpm_public_key_path": agent_info["tpm_public_key_path"],
                    "geolocation": agent_info["geolocation"],
                    "status": agent_info["status"],
                    "created_at": agent_info["created_at"]
                }
                
                allowlist.append(allowlist_entry)
            
            # Write allowlist
            with open(self.allowlist_path, 'w') as f:
                json.dump(allowlist, f, indent=2)
            
            logger.info("Allowlist updated", 
                       allowlist_path=str(self.allowlist_path),
                       agent_count=len(allowlist))
            
            return True
            
        except Exception as e:
            logger.error("Failed to update allowlist", error=str(e))
            return False
    
    def _get_timestamp(self) -> str:
        """Get current timestamp in ISO format."""
        from datetime import datetime
        return datetime.utcnow().isoformat()


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Manage agent configurations')
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Create command
    create_parser = subparsers.add_parser('create', help='Create a new agent')
    create_parser.add_argument('agent_name', help='Name of the agent')
    create_parser.add_argument('country', help='Country code (e.g., US)')
    create_parser.add_argument('state', help='State or province')
    create_parser.add_argument('city', help='City name')
    create_parser.add_argument('--description', help='Optional description')
    
    # List command
    subparsers.add_parser('list', help='List all agents')
    
    # Info command
    info_parser = subparsers.add_parser('info', help='Get agent information')
    info_parser.add_argument('agent_name', help='Name of the agent')
    
    # Update allowlist command
    subparsers.add_parser('update-allowlist', help='Update collector allowlist')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    manager = AgentManager()
    
    if args.command == 'create':
        success = manager.create_agent(
            args.agent_name,
            args.country,
            args.state,
            args.city,
            args.description
        )
        if success:
            print(f"✅ Agent '{args.agent_name}' created successfully")
        else:
            print(f"❌ Failed to create agent '{args.agent_name}'")
            sys.exit(1)
    
    elif args.command == 'list':
        agents = manager.list_agents()
        if agents:
            print("📋 Configured Agents:")
            for agent in agents:
                print(f"  - {agent}")
        else:
            print("📋 No agents configured")
    
    elif args.command == 'info':
        try:
            agent_info = manager.get_agent_info(args.agent_name)
            print(f"📋 Agent Information for '{args.agent_name}':")
            print(json.dumps(agent_info, indent=2))
        except FileNotFoundError:
            print(f"❌ Agent '{args.agent_name}' not found")
            sys.exit(1)
    
    elif args.command == 'update-allowlist':
        success = manager.update_allowlist()
        if success:
            print("✅ Allowlist updated successfully")
        else:
            print("❌ Failed to update allowlist")
            sys.exit(1)


if __name__ == "__main__":
    main()
