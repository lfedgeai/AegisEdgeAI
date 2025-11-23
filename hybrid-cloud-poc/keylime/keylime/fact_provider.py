"""
Unified-Identity - Unified-Identity: Hardware Integration & Delegated Certification

This module provides attested facts (geolocation) for the Unified Identity flow.
Facts are retrieved from the registrar or a simple fact store.
"""

import hashlib
from typing import Any, Dict, Optional

from keylime import config, keylime_logging
from keylime.db.keylime_db import SessionManager, make_engine
from keylime.db.verifier_db import VerfierMain

logger = keylime_logging.init_logging("fact_provider")


# Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
def get_host_identifier_from_ek(tpm_ek: Optional[str]) -> Optional[str]:
    """
    Generate a host identifier from TPM EK.

    Args:
        tpm_ek: TPM Endorsement Key (base64 or PEM)

    Returns:
        Host identifier string (hash of EK), or None on error
    """
    if not tpm_ek:
        return None

    try:
        # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
        # Create a stable identifier from EK
        ek_bytes = tpm_ek.encode("utf-8") if isinstance(tpm_ek, str) else tpm_ek
        ek_hash = hashlib.sha256(ek_bytes).hexdigest()
        return f"ek-{ek_hash[:16]}"
    except Exception as e:
        logger.error("Unified-Identity - Unified-Identity: Failed to generate host identifier from EK: %s", e)
        return None


# Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
def get_host_identifier_from_ak(tpm_ak: Optional[str]) -> Optional[str]:
    """
    Generate a host identifier from TPM AK.

    Args:
        tpm_ak: TPM Attestation Key (base64 or PEM)

    Returns:
        Host identifier string (hash of AK), or None on error
    """
    if not tpm_ak:
        return None

    try:
        # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
        # Create a stable identifier from AK
        ak_bytes = tpm_ak.encode("utf-8") if isinstance(tpm_ak, str) else tpm_ak
        ak_hash = hashlib.sha256(ak_bytes).hexdigest()
        return f"ak-{ak_hash[:16]}"
    except Exception as e:
        logger.error("Unified-Identity - Unified-Identity: Failed to generate host identifier from AK: %s", e)
        return None


# Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
def get_attested_claims(
    tpm_ek: Optional[str] = None,
    tpm_ak: Optional[str] = None,
    agent_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Retrieve attested claims (geolocation) for a host.

    Facts are retrieved from:
    1. Verifier database (if agent is registered with verifier and has metadata)
    2. Simple fact store (using host identifier derived from TPM EK/AK)

    If no facts are available, returns an empty dictionary.

    Args:
        tpm_ek: TPM Endorsement Key (optional, for host identification)
        tpm_ak: TPM Attestation Key (optional, for host identification)
        agent_id: Agent ID (optional, if host is registered)

    Returns:
        Dictionary containing attested claims (may be empty if no facts available):
        {
            "geolocation": dict (optional) - {"type": "mobile|gnss", "sensor_id": "...", "value": "..."}
        }
    """
    logger.info("Unified-Identity - Unified-Identity: Retrieving attested claims")

    # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
    # Try to retrieve facts from verifier database if agent_id is provided
    if agent_id:
        try:
            from keylime.db.keylime_db import SessionManager

            engine = make_engine("cloud_verifier")
            with SessionManager().session_context(engine) as session:
                agent = session.query(VerfierMain).filter(VerfierMain.agent_id == agent_id).first()
                if agent:
                    # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
                    # Check if agent has metadata with facts
                    if agent.meta_data:
                        try:
                            import json

                            metadata = json.loads(agent.meta_data) if isinstance(agent.meta_data, str) else agent.meta_data
                            if isinstance(metadata, dict):
                                # Only return facts that are actually present in metadata
                                facts = {}
                                if "geolocation" in metadata:
                                    facts["geolocation"] = metadata["geolocation"]

                                logger.info(
                                    "Unified-Identity - Unified-Identity: Retrieved facts from agent metadata for agent %s",
                                    agent_id,
                                )
                                return facts
                        except Exception as e:
                            logger.warning(
                                "Unified-Identity - Unified-Identity: Failed to parse agent metadata: %s", e
                            )
        except Exception as e:
            logger.warning("Unified-Identity - Unified-Identity: Failed to retrieve facts from database: %s", e)

    # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
    # Try to identify host from EK or AK and retrieve from fact store
    host_id = None
    if tpm_ek:
        host_id = get_host_identifier_from_ek(tpm_ek)
    elif tpm_ak:
        host_id = get_host_identifier_from_ak(tpm_ak)

    if host_id:
        # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
        # In Unified-Identity, we use a simple in-memory fact store
        # In production, this would query a proper fact database
        facts = _get_facts_from_store(host_id)
        if facts:
            logger.info("Unified-Identity - Unified-Identity: Retrieved facts from fact store for host %s", host_id)
            return facts

    # Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
    # No facts available - return empty dict
    logger.info("Unified-Identity - Unified-Identity: No attested claims available (agent not registered with verifier or no fact store entry)")
    return {}


# Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
# Simple in-memory fact store (for Unified-Identity testing)
_fact_store: Dict[str, Dict[str, Any]] = {}


def _get_facts_from_store(host_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve facts from the simple fact store.

    Args:
        host_id: Host identifier

    Returns:
        Facts dictionary or None if not found
    """
    return _fact_store.get(host_id)


# Unified-Identity - Unified-Identity: Core Keylime Functionality (Fact-Provider Logic)
def set_facts_in_store(host_id: str, facts: Dict[str, Any]) -> None:
    """
    Store facts in the simple fact store (for testing).

    Args:
        host_id: Host identifier
        facts: Facts dictionary
    """
    _fact_store[host_id] = facts
    logger.debug("Unified-Identity - Unified-Identity: Stored facts for host %s", host_id)

