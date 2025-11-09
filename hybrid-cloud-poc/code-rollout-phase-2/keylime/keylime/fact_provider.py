"""
Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)

This module provides attested facts (geolocation, host integrity, GPU metrics)
for the Unified Identity flow. In Phase 2, facts are retrieved from the registrar
or a simple fact store.
"""

import hashlib
from typing import Any, Dict, Optional

from keylime import config, keylime_logging
from keylime.db.keylime_db import SessionManager, make_engine
from keylime.db.verifier_db import VerfierMain

logger = keylime_logging.init_logging("fact_provider")


# Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
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
        # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
        # Create a stable identifier from EK
        ek_bytes = tpm_ek.encode("utf-8") if isinstance(tpm_ek, str) else tpm_ek
        ek_hash = hashlib.sha256(ek_bytes).hexdigest()
        return f"ek-{ek_hash[:16]}"
    except Exception as e:
        logger.error("Unified-Identity - Phase 2: Failed to generate host identifier from EK: %s", e)
        return None


# Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
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
        # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
        # Create a stable identifier from AK
        ak_bytes = tpm_ak.encode("utf-8") if isinstance(tpm_ak, str) else tpm_ak
        ak_hash = hashlib.sha256(ak_bytes).hexdigest()
        return f"ak-{ak_hash[:16]}"
    except Exception as e:
        logger.error("Unified-Identity - Phase 2: Failed to generate host identifier from AK: %s", e)
        return None


# Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
def get_attested_claims(
    tpm_ek: Optional[str] = None,
    tpm_ak: Optional[str] = None,
    agent_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Retrieve attested claims (geolocation, host integrity, GPU metrics) for a host.

    In Phase 2, facts are retrieved from:
    1. Verifier database (if agent is registered)
    2. Configuration-based defaults
    3. Simple fact store (for testing)

    Args:
        tpm_ek: TPM Endorsement Key (optional, for host identification)
        tpm_ak: TPM Attestation Key (optional, for host identification)
        agent_id: Agent ID (optional, if host is registered)

    Returns:
        Dictionary containing attested claims:
        {
            "geolocation": str,
            "host_integrity_status": str,
            "gpu_metrics_health": {
                "status": str,
                "utilization_pct": float,
                "memory_mb": int
            }
        }
    """
    logger.info("Unified-Identity - Phase 2: Retrieving attested claims")

    # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
    # Default values (can be overridden by configuration or database)
    default_geolocation = config.get(
        "verifier", "unified_identity_default_geolocation", fallback="Spain: N40.4168, W3.7038"
    )
    default_integrity = config.get(
        "verifier", "unified_identity_default_integrity", fallback="passed_all_checks"
    )
    default_gpu_status = config.get("verifier", "unified_identity_default_gpu_status", fallback="healthy")
    default_gpu_utilization = config.getfloat("verifier", "unified_identity_default_gpu_utilization", fallback=15.0)
    default_gpu_memory = config.getint("verifier", "unified_identity_default_gpu_memory", fallback=10240)

    # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
    # Try to retrieve facts from verifier database if agent_id is provided
    if agent_id:
        try:
            from keylime.db.keylime_db import SessionManager

            engine = make_engine("cloud_verifier")
            with SessionManager().session_context(engine) as session:
                agent = session.query(VerfierMain).filter(VerfierMain.agent_id == agent_id).first()
                if agent:
                    # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
                    # Check if agent has metadata with facts
                    if agent.meta_data:
                        try:
                            import json

                            metadata = json.loads(agent.meta_data) if isinstance(agent.meta_data, str) else agent.meta_data
                            if isinstance(metadata, dict):
                                geolocation = metadata.get("geolocation", default_geolocation)
                                integrity = metadata.get("host_integrity_status", default_integrity)
                                gpu_metrics = metadata.get("gpu_metrics_health", {})
                                if isinstance(gpu_metrics, dict):
                                    gpu_status = gpu_metrics.get("status", default_gpu_status)
                                    gpu_utilization = gpu_metrics.get("utilization_pct", default_gpu_utilization)
                                    gpu_memory = gpu_metrics.get("memory_mb", default_gpu_memory)
                                else:
                                    gpu_status = default_gpu_status
                                    gpu_utilization = default_gpu_utilization
                                    gpu_memory = default_gpu_memory

                                logger.info(
                                    "Unified-Identity - Phase 2: Retrieved facts from agent metadata for agent %s",
                                    agent_id,
                                )
                                return {
                                    "geolocation": geolocation,
                                    "host_integrity_status": integrity,
                                    "gpu_metrics_health": {
                                        "status": gpu_status,
                                        "utilization_pct": float(gpu_utilization),
                                        "memory_mb": int(gpu_memory),
                                    },
                                }
                        except Exception as e:
                            logger.warning(
                                "Unified-Identity - Phase 2: Failed to parse agent metadata, using defaults: %s", e
                            )
        except Exception as e:
            logger.warning("Unified-Identity - Phase 2: Failed to retrieve facts from database: %s", e)

    # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
    # Try to identify host from EK or AK and retrieve from fact store
    host_id = None
    if tpm_ek:
        host_id = get_host_identifier_from_ek(tpm_ek)
    elif tpm_ak:
        host_id = get_host_identifier_from_ak(tpm_ak)

    if host_id:
        # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
        # In Phase 2, we use a simple in-memory fact store
        # In production, this would query a proper fact database
        facts = _get_facts_from_store(host_id)
        if facts:
            logger.info("Unified-Identity - Phase 2: Retrieved facts from fact store for host %s", host_id)
            return facts

    # Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
    # Return default facts
    logger.info("Unified-Identity - Phase 2: Using default facts")
    return {
        "geolocation": default_geolocation,
        "host_integrity_status": default_integrity,
        "gpu_metrics_health": {
            "status": default_gpu_status,
            "utilization_pct": float(default_gpu_utilization),
            "memory_mb": int(default_gpu_memory),
        },
    }


# Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
# Simple in-memory fact store (for Phase 2 testing)
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


# Unified-Identity - Phase 2: Core Keylime Functionality (Fact-Provider Logic)
def set_facts_in_store(host_id: str, facts: Dict[str, Any]) -> None:
    """
    Store facts in the simple fact store (for testing).

    Args:
        host_id: Host identifier
        facts: Facts dictionary
    """
    _fact_store[host_id] = facts
    logger.debug("Unified-Identity - Phase 2: Stored facts for host %s", host_id)

