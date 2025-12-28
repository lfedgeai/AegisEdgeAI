# Security Policy

## Reporting Security Vulnerabilities

The AegisSovereignAI team takes security seriously. We appreciate your efforts to responsibly disclose your findings.

### DO NOT Report Security Vulnerabilities Publicly

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

### How to Report

To report a security vulnerability, please use one of the following methods:

1. **GitHub Security Advisories** (Preferred)
   - Go to the [Security Advisories](https://github.com/lfedgeai/AegisSovereignAI/security/advisories) page
   - Click "Report a vulnerability"
   - Fill out the form with details

2. **Email**
   - Send an email to: security@lfedge.org
   - Include "AegisSovereignAI Security" in the subject line

### What to Include

Please include the following information in your report:

- **Description**: Clear description of the vulnerability
- **Impact**: Potential impact and severity assessment
- **Reproduction Steps**: Detailed steps to reproduce the issue
- **Affected Versions**: Which versions are affected
- **Suggested Fix**: If you have ideas for remediation (optional)
- **Your Contact**: How we can reach you for follow-up

### Response Timeline

| Action | Timeline |
|--------|----------|
| Initial acknowledgment | Within 48 hours |
| Severity assessment | Within 5 business days |
| Fix development | Depends on severity |
| Security advisory | After fix is available |

### Severity Levels

| Level | Description | Target Fix Time |
|-------|-------------|-----------------|
| **Critical** | Remote code execution, credential theft | 24-48 hours |
| **High** | Privilege escalation, data exposure | 7 days |
| **Medium** | Limited impact vulnerabilities | 30 days |
| **Low** | Minor issues, defense in depth | Next release |

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | ✅ Yes |
| hybrid-cloud-poc branch | ✅ Yes |
| Other branches | ❌ No |

> **Note**: This project is currently in Proof of Concept stage. Security updates will be applied to the main and hybrid-cloud-poc branches.

## Security Considerations

### TPM and Hardware Security

This project relies on TPM 2.0 for hardware-rooted trust. Security considerations:

- **TPM Ownership**: Ensure TPM ownership is properly configured
- **Key Storage**: TPM keys should not be exported or backed up insecurely
- **Attestation**: Verify attestation quotes are properly validated

### Network Security

- **mTLS**: All service-to-service communication should use mTLS
- **Certificate Validation**: Never use `InsecureSkipVerify` in production
- **API Authentication**: All APIs require proper authentication

### Secrets Management

- **No Hardcoded Secrets**: Never commit secrets to the repository
- **Environment Variables**: Use environment variables or secret managers
- **CAMARA API Keys**: Store telco API credentials securely

## Security Best Practices for Deployment

### Production Checklist

- [ ] TPM 2.0 hardware available and configured
- [ ] All components using TLS with valid certificates
- [ ] Secrets stored in secure secret manager
- [ ] Network policies restricting component communication
- [ ] Audit logging enabled
- [ ] Regular security updates applied

### Not Recommended for Production

The following configurations are for development/testing only:

- Software TPM (swtpm) - use hardware TPM in production
- Self-signed certificates without proper CA
- `InsecureSkipVerify` in any TLS configuration
- Hardcoded credentials in configuration files

## Acknowledgments

We will acknowledge security researchers who report valid vulnerabilities (unless they prefer to remain anonymous) in our security advisories.

## Contact

For security-related questions that are not vulnerability reports, please open a [GitHub Discussion](https://github.com/lfedgeai/AegisSovereignAI/discussions) with the "security" label.

