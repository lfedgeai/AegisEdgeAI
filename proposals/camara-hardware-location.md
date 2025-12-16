# Proposal: Hardware-Verified "Premium Tier" for CAMARA Location APIs

**Status:** Strategic Proposal (Submitted to Deutsche Telekom T-Challenge)
**Target Group:** CAMARA Project (Device Location VR) / GSMA Open Gateway
**Project Lead:** Ramki Krishnan (Vishanti Systems)

## 1\. Executive Summary

This proposal outlines an architectural extension to the **CAMARA Device Location Verification API**.

We propose introducing a **"Premium Tier"** for location services that moves beyond standard Network Assurance (Cell Tower Triangulation) to **Hardware Assurance** (TPM + GNSS Attestation). This extension enables Telcos to offer unforgeable "Proof of Residency" to regulated industries (Banking, Defense, Healthcare) that require audit-proof compliance with data sovereignty laws (e.g., GDPR, EUDR).

## 2\. The Problem: The "Trust Gap" in Location APIs

Current CAMARA location APIs rely on network-side triangulation or user-provided GPS coordinates. While effective for consumer apps, these methods have critical gaps for high-security use cases:

  * **SIM Swapping Risks:** Location is often tied to the SIM (IMSI), not the device hardware. If a SIM is moved to an unauthorized device, the API still validates the location.
  * **GPS Spoofing:** Standard "User Plane" GPS data can be easily mocked by malicious apps or VPNs.
  * **Lack of Audit Trail:** Regulators often require cryptographic proof of *exactly which hardware* processed the data, not just a "Yes/No" from the network.

## 3\. The Solution: Hardware-Rooted Verification

We propose extending the `verify_location` API schema to include an optional **Hardware Integrity Proof**.

**AegisSovereignAI** acts as the "Trust Middleware" that generates and validates this proof, cryptographically binding the **Physical Location** (GNSS) to the **Device Identity** (TPM).

### Proposed Workflow:

1.  **Client App with Device:** Generates a "Unified SVID" containing a TPM Quote which binds:
      * Mobile Sensor Manufacturer ID / IMEI / IMSI
      * GPS-Sensor Manufacturer ID / Device Serial Number
      * Precise Location Data (GPS-based)
2.  **Server-side API Gateway:** Calls the CAMARA API, embedding this SVID in the request header (e.g., `X-Device-Attestation`).
3.  **CAMARA API Gateway:** Forwards the token to the **AegisSovereignAI Verifier**.
4.  **Verification:**
      * *Check 1:* Is the TPM signature valid? (Anti-Cloning)
      * *Check 2:* Is the Mobile Sensor Manufacturer ID/IMEI/IMSI valid? (Anti-Spoofing / Anti-SIM-Swap)
      * *Check 3:* Is the GPS data signed by the trusted sensor? (Anti-Spoofing)
      * *Check 4:* Is the device physically within the cell tower's range? (Cross-Verification)
5.  **Response:** Returns `true` only if **ALL** the checks pass.

## 4\. Business Value for Telcos

This extension transforms the Location API from a commodity utility into a high-margin security product.

| Feature | Standard API (Current) | Premium API (Proposed) |
| :--- | :--- | :--- |
| **Verification Source** | Network Signal | Network + Silicon (TPM) |
| **Target Customer** | Ride-sharing, Logistics | Banks, Gov/Defense, Hospitals |
| **Value Prop** | "Approximate Location" | **"Legal Proof of Residency"** |
| **Use Case** | Routing, Fraud Check | **Sovereign Cloud, EUDR Compliance** |

## 5\. Alignment with Open Standards

This proposal leverages existing standards to ensure interoperability:

  * **IETF RATS:** For the structure of the Attestation Token.
  * **CNCF SPIFFE:** For the device identity format.
  * **CAMARA:** As the standard interface for consumption.

## 6\. Proof of Concept

A reference implementation of this architecture is currently available in the **[AegisEdgeAI Sovereign Hybrid Cloud PoC](https://github.com/lfedgeai/AegisEdgeAI/tree/main/hybrid-cloud-poc)**.

  * It demonstrates a **Mobile Location Service** that acts as a mock CAMARA gateway.
  * It enforces access control based on real-time TPM attestation of a USB-tethered mobile sensor.