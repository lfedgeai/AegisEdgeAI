#!/usr/bin/env python3
"""
Create a new agent with complete setup.

Usage:
    python create_agent.py <agent_name> [--location country/state/city]
    
Example:
    python create_agent.py agent-003
    python create_agent.py agent-003 --location "US/Texas/Houston"
"""

import os
import sys
import json
import shutil
import argparse
from pathlib import Path
from typing import Dict, Any
import structlog

# Add parent directory to path for imports
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

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


class AgentCreator:
    """Agent creation and setup utility."""
    
    def __init__(self, agent_name: str, location: str = "US/California/Santa Clara"):
        """
        Initialize agent creator.
        
        Args:
            agent_name: Name of the agent (e.g., 'agent-003')
            location: Location in format "country/state/city"
        """
        self.agent_name = agent_name
        self.location_parts = location.split('/')
        if len(self.location_parts) != 3:
            raise ValueError("Location must be in format 'country/state/city'")
        
        self.country, self.state, self.city = self.location_parts
        self.agent_dir = f"agents/{agent_name}"
        self.config_path = f"{self.agent_dir}/config.json"
        
    def create_agent_directory(self):
        """Create agent directory structure."""
        logger.info("Creating agent directory", agent_name=self.agent_name)
        
        # Create agent directory
        os.makedirs(self.agent_dir, exist_ok=True)
        logger.info("Agent directory created", path=self.agent_dir)
        
    def create_agent_config(self):
        """Create agent configuration file."""
        logger.info("Creating agent configuration", agent_name=self.agent_name)
        
        config = {
            "agent_name": self.agent_name,
            "tpm_public_key_path": f"tpm/{self.agent_name}_pubkey.pem",
            "tpm_context_file": f"tpm/{self.agent_name}.ctx",
            "description": f"Edge AI agent for {self.city}, {self.state} deployment",
            "created_at": "2025-08-15T18:00:00Z",
            "status": "active"
        }
        
        with open(self.config_path, 'w') as f:
            json.dump(config, f, indent=2)
        
        logger.info("Agent configuration created", config_path=self.config_path)
        
    def create_tpm_files(self):
        """Create agent-specific TPM context and public key files."""
        logger.info("Creating TPM files", agent_name=self.agent_name)
        
        # Base files to copy from
        base_context = "tpm/app.ctx"
        base_public_key = "tpm/appsk_pubkey.pem"
        
        # Agent-specific files
        agent_context = f"tpm/{self.agent_name}.ctx"
        agent_public_key = f"tpm/{self.agent_name}_pubkey.pem"
        
        # Copy context file
        if os.path.exists(base_context):
            shutil.copy2(base_context, agent_context)
            logger.info("TPM context file created", context_file=agent_context)
        else:
            logger.warning("Base TPM context not found, skipping", base_file=base_context)
        
        # Copy public key file
        if os.path.exists(base_public_key):
            shutil.copy2(base_public_key, agent_public_key)
            logger.info("TPM public key file created", public_key_file=agent_public_key)
        else:
            logger.warning("Base TPM public key not found, skipping", base_file=base_public_key)
        
    def setup_tpm_persistence(self):
        """Run TPM persistence setup for the agent."""
        logger.info("Setting up TPM persistence", agent_name=self.agent_name)
        
        try:
            import subprocess
            
            # Run tpm-app-persist.sh with agent-specific parameters
            cmd = [
                "bash", "tpm/tpm-app-persist.sh", 
                "--force", 
                f"{self.agent_name}.ctx", 
                f"{self.agent_name}_pubkey.pem"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=".")
            
            if result.returncode == 0:
                logger.info("TPM persistence setup completed", agent_name=self.agent_name)
            else:
                logger.warning("TPM persistence setup failed", 
                             agent_name=self.agent_name,
                             error=result.stderr)
                
        except Exception as e:
            logger.warning("TPM persistence setup failed", 
                         agent_name=self.agent_name,
                         error=str(e))
        
    def add_to_collector_allowlist(self):
        """Add agent to collector allowlist."""
        logger.info("Adding agent to collector allowlist", agent_name=self.agent_name)
        
        allowlist_path = "collector/allowed_agents.json"
        
        # Load existing allowlist
        if os.path.exists(allowlist_path):
            with open(allowlist_path, 'r') as f:
                allowed_agents = json.load(f)
        else:
            allowed_agents = []
        
        # Read the actual public key content
        public_key_content = self._read_public_key_content()
        
        # Check if agent already exists and update it
        for i, agent in enumerate(allowed_agents):
            if agent.get('agent_name') == self.agent_name:
                logger.info("Agent already exists in allowlist, updating", agent_name=self.agent_name)
                # Update the existing agent entry
                allowed_agents[i] = {
                    "agent_name": self.agent_name,
                    "tpm_public_key": public_key_content,  # Store actual public key content
                    "geolocation": {
                        "country": self.country,
                        "state": self.state,
                        "city": self.city
                    },
                    "status": "active",
                    "created_at": "2025-08-15T18:00:00Z"
                }
                
                # Write back to allowlist
                with open(allowlist_path, 'w') as f:
                    json.dump(allowed_agents, f, indent=2)
                
                logger.info("Agent updated in collector allowlist", agent_name=self.agent_name)
                return
        
        # Add new agent entry
        new_agent = {
            "agent_name": self.agent_name,
            "tpm_public_key": public_key_content,  # Store actual public key content
            "geolocation": {
                "country": self.country,
                "state": self.state,
                "city": self.city
            },
            "status": "active",
            "created_at": "2025-08-15T18:00:00Z"
        }
        
        allowed_agents.append(new_agent)
        
        # Write back to allowlist
        with open(allowlist_path, 'w') as f:
            json.dump(allowed_agents, f, indent=2)
        
        logger.info("Agent added to collector allowlist", agent_name=self.agent_name)
        
    def _read_public_key_content(self):
        """Read the raw public key content from the TPM public key file."""
        public_key_file = f"tpm/{self.agent_name}_pubkey.pem"
        
        if not os.path.exists(public_key_file):
            logger.warning("Public key file not found, using base public key", public_key_file=public_key_file)
            public_key_file = "tpm/appsk_pubkey.pem"
        
        try:
            # Read the raw public key content
            with open(public_key_file, 'r') as f:
                public_key_content = f.read().strip()
            
            logger.info("Public key content read successfully", 
                       public_key_file=public_key_file,
                       key_size_chars=len(public_key_content))
            
            return public_key_content
            
        except Exception as e:
            logger.error("Failed to read public key content", 
                        public_key_file=public_key_file,
                        error=str(e))
            raise
        
    def create_agent(self):
        """Create complete agent setup."""
        logger.info("Starting agent creation", agent_name=self.agent_name)
        
        try:
            # Step 1: Create directory structure
            self.create_agent_directory()
            
            # Step 2: Create agent configuration
            self.create_agent_config()
            
            # Step 3: Create TPM files
            self.create_tpm_files()
            
            # Step 4: Setup TPM persistence (optional)
            self.setup_tpm_persistence()
            
            # Step 5: Add to collector allowlist
            self.add_to_collector_allowlist()
            
            logger.info("Agent creation completed successfully", agent_name=self.agent_name)
            return True
            
        except Exception as e:
            logger.error("Agent creation failed", agent_name=self.agent_name, error=str(e))
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Create a new agent with complete setup')
    parser.add_argument('agent_name', help='Name of the agent (e.g., agent-003)')
    parser.add_argument('--location', default='US/California/Santa Clara',
                       help='Location in format "country/state/city" (default: US/California/Santa Clara)')
    
    args = parser.parse_args()
    
    print(f"🔧 Creating agent: {args.agent_name}")
    print(f"📍 Location: {args.location}")
    print(f"📁 Agent directory: agents/{args.agent_name}")
    
    try:
        creator = AgentCreator(args.agent_name, args.location)
        success = creator.create_agent()
        
        if success:
            # Calculate agent port and APP_HANDLE for display
            agent_number = int(args.agent_name.split('-')[-1])
            agent_port = 8401 + agent_number - 1
            base_handle = int("0x8101000B", 16)
            agent_handle = base_handle + agent_number - 1
            agent_app_handle = f"0x{agent_handle:08X}"
            
            print(f"\n✅ Agent '{args.agent_name}' created successfully!")
            print(f"📋 Next steps:")
            print(f"   1. Start the agent: python start_agent.py {args.agent_name}")
            print(f"   2. Agent will run on port: {agent_port}")
            print(f"   3. Agent will use APP_HANDLE: {agent_app_handle}")
            print(f"   4. Set geographic region: export {args.agent_name.upper().replace('-', '_')}_GEOGRAPHIC_REGION=EU")
            print(f"   5. Check agent status: curl https://localhost:{agent_port}/metrics/status")
        else:
            print(f"\n❌ Failed to create agent '{args.agent_name}'")
            sys.exit(1)
            
    except Exception as e:
        print(f"\n❌ Error creating agent: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
