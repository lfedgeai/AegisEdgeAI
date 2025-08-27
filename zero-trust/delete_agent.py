#!/usr/bin/env python3
"""
Delete an agent and clean up all associated files.

Usage:
    python delete_agent.py <agent_name> [--force]
    
Example:
    python delete_agent.py agent-003
    python delete_agent.py agent-003 --force
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


class AgentDeleter:
    """Agent deletion and cleanup utility."""
    
    def __init__(self, agent_name: str, force: bool = False):
        """
        Initialize agent deleter.
        
        Args:
            agent_name: Name of the agent to delete (e.g., 'agent-003')
            force: Force deletion without confirmation
        """
        self.agent_name = agent_name
        self.force = force
        self.agent_dir = f"agents/{agent_name}"
        self.config_path = f"{self.agent_dir}/config.json"
        
    def check_agent_exists(self):
        """Check if the agent exists."""
        if not os.path.exists(self.agent_dir):
            raise FileNotFoundError(f"Agent directory not found: {self.agent_dir}")
        
        if not os.path.exists(self.config_path):
            raise FileNotFoundError(f"Agent config not found: {self.config_path}")
        
        logger.info("Agent found", agent_name=self.agent_name, config_path=self.config_path)
        
    def load_agent_config(self):
        """Load agent configuration to get file paths."""
        try:
            with open(self.config_path, 'r') as f:
                config = json.load(f)
            return config
        except Exception as e:
            logger.warning("Failed to load agent config", agent_name=self.agent_name, error=str(e))
            return {}
        
    def remove_from_collector_allowlist(self):
        """Remove agent from collector allowlist."""
        logger.info("Removing agent from collector allowlist", agent_name=self.agent_name)
        
        allowlist_path = "collector/allowed_agents.json"
        
        if not os.path.exists(allowlist_path):
            logger.warning("Collector allowlist not found", allowlist_path=allowlist_path)
            return
        
        # Load existing allowlist
        with open(allowlist_path, 'r') as f:
            allowed_agents = json.load(f)
        
        # Remove agent entry
        original_count = len(allowed_agents)
        allowed_agents = [agent for agent in allowed_agents if agent.get('agent_name') != self.agent_name]
        
        if len(allowed_agents) < original_count:
            # Write back to allowlist
            with open(allowlist_path, 'w') as f:
                json.dump(allowed_agents, f, indent=2)
            logger.info("Agent removed from collector allowlist", agent_name=self.agent_name)
        else:
            logger.warning("Agent not found in collector allowlist", agent_name=self.agent_name)
    
    def remove_from_gateway_allowlist(self):
        """Remove agent from gateway allowlist."""
        logger.info("Removing agent from gateway allowlist", agent_name=self.agent_name)
        
        allowlist_path = "gateway/allowed_agents.json"
        
        if not os.path.exists(allowlist_path):
            logger.warning("Gateway allowlist not found", allowlist_path=allowlist_path)
            return
        
        # Load existing allowlist
        with open(allowlist_path, 'r') as f:
            allowed_agents = json.load(f)
        
        # Remove agent entry
        original_count = len(allowed_agents)
        allowed_agents = [agent for agent in allowed_agents if agent.get('agent_name') != self.agent_name]
        
        if len(allowed_agents) < original_count:
            # Write back to allowlist
            with open(allowlist_path, 'w') as f:
                json.dump(allowed_agents, f, indent=2)
            logger.info("Agent removed from gateway allowlist", agent_name=self.agent_name)
        else:
            logger.warning("Agent not found in gateway allowlist", agent_name=self.agent_name)
        
    def delete_tpm_files(self, config):
        """Delete agent-specific TPM files."""
        logger.info("Deleting TPM files", agent_name=self.agent_name)
        
        # Get TPM file paths from config
        tpm_context_file = config.get('tpm_context_file', f"tpm/{self.agent_name}.ctx")
        tpm_public_key_file = config.get('tpm_public_key_path', f"tpm/{self.agent_name}_pubkey.pem")
        
        # Delete context file
        if os.path.exists(tpm_context_file):
            os.remove(tpm_context_file)
            logger.info("TPM context file deleted", context_file=tpm_context_file)
        else:
            logger.warning("TPM context file not found", context_file=tpm_context_file)
        
        # Delete public key file
        if os.path.exists(tpm_public_key_file):
            os.remove(tpm_public_key_file)
            logger.info("TPM public key file deleted", public_key_file=tpm_public_key_file)
        else:
            logger.warning("TPM public key file not found", public_key_file=tpm_public_key_file)
        
    def delete_agent_directory(self):
        """Delete agent directory and all contents."""
        logger.info("Deleting agent directory", agent_name=self.agent_name)
        
        if os.path.exists(self.agent_dir):
            shutil.rmtree(self.agent_dir)
            logger.info("Agent directory deleted", agent_dir=self.agent_dir)
        else:
            logger.warning("Agent directory not found", agent_dir=self.agent_dir)
        
    def confirm_deletion(self):
        """Confirm deletion with user."""
        if self.force:
            return True
        
        print(f"\n⚠️  WARNING: This will permanently delete agent '{self.agent_name}'")
        print(f"   - Agent directory: {self.agent_dir}")
        print(f"   - TPM context and public key files")
        print(f"   - Collector allowlist entry")
        print(f"   - Gateway allowlist entry")
        print(f"   - All agent configuration")
        
        response = input(f"\nAre you sure you want to delete agent '{self.agent_name}'? (yes/no): ")
        return response.lower() in ['yes', 'y']
        
    def delete_agent(self):
        """Delete complete agent setup."""
        logger.info("Starting agent deletion", agent_name=self.agent_name)
        
        try:
            # Step 1: Check if agent exists
            self.check_agent_exists()
            
            # Step 2: Load agent config
            config = self.load_agent_config()
            
            # Step 3: Confirm deletion
            if not self.confirm_deletion():
                logger.info("Agent deletion cancelled by user", agent_name=self.agent_name)
                return True
            
            # Step 4: Remove from collector allowlist
            self.remove_from_collector_allowlist()
            
            # Step 5: Remove from gateway allowlist
            self.remove_from_gateway_allowlist()
            
            # Step 6: Delete TPM files
            self.delete_tpm_files(config)
            
            # Step 7: Delete agent directory
            self.delete_agent_directory()
            
            logger.info("Agent deletion completed successfully", agent_name=self.agent_name)
            return True
            
        except Exception as e:
            logger.error("Agent deletion failed", agent_name=self.agent_name, error=str(e))
            return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Delete an agent and clean up all associated files')
    parser.add_argument('agent_name', help='Name of the agent to delete (e.g., agent-003)')
    parser.add_argument('--force', action='store_true', help='Force deletion without confirmation')
    
    args = parser.parse_args()
    
    print(f"🗑️  Deleting agent: {args.agent_name}")
    print(f"📁 Agent directory: agents/{args.agent_name}")
    
    if args.force:
        print("⚠️  Force mode enabled - no confirmation required")
    
    try:
        deleter = AgentDeleter(args.agent_name, args.force)
        success = deleter.delete_agent()
        
        if success:
            print(f"\n✅ Agent '{args.agent_name}' deleted successfully!")
            print(f"📋 Cleanup completed:")
            print(f"   - Agent directory removed")
            print(f"   - TPM files deleted")
            print(f"   - Collector allowlist updated")
            print(f"   - Gateway allowlist updated")
        else:
            print(f"\n❌ Failed to delete agent '{args.agent_name}'")
            sys.exit(1)
            
    except Exception as e:
        print(f"\n❌ Error deleting agent: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
