# Current Federation Model between Enterprise and Service Provider
- Enterprise owns IDP; Identity federation between Enterprise and Service Provider
- Enterprise signs Identity token with claims such as role
- Service Provider verifies Enterprise IDP token using the configured public key of the Enterprise
- Service Provider mints Authorization token with the same claims such as role from the Identity token
- Service Provider policy engine is configured by Enterprise to perform specific actions for application based on fields in Identity token which are inherited by the Authorization token

# New claims additions to Identity Token and thus the Authorization Token
- HW-rooted TPM attestation of workload 
- HW-rooted TPM attested Geographic location of workload 

Note: These new claims can be conveyed in HTTP extension header as part of every HTTP request (see section 8.1 in https://github.com/nedmsmith/draft-klspa-wimse-verifiable-geo-fence/blob/main/draft-lkspa-wimse-verifiable-geo-fence.md)
