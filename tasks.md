Tasks - 09/27/2025
==================
Very good meeting last week, summarizing next steps
- Akhil to make progress on Host GPU integrity plugin with NVIDIA integration as the first target
- Clyde could possibly look at Host geolocation plugin 
- Pranav will look at Host proximity plugin 
- Vijay and Ramki to look at Spire/Keylime integration along with Spire TPM plugin

Programming language recommendation for plugins: Go or C/C++ which can be statically compiled and a programming language well known to us; Rust has a steep learning curve.
---------------------------------------------------------------
Task : Spire/Keylime integration along with Spire TPM plugin:
Note : TPM app key is inside TPM, use tpm2 access broker
1. Spire TPM plugin API ( golang implementation )
   a. Create TPM app key
   b. Delete TPM app key
   c. Sign with TPM app key
   d. Verify signature by TPM app key
   6. Generate TPM Certificate with TPM app key
2. Create a makefile which should build tpm c functions with cgo library, c libraries should be linked as static
   
