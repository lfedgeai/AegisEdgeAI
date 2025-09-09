# Goal
Make software TPM and TPM tools available for MAC developer community

# Benefits of Software TPM and TPM tools for MAC developer community
1. Wider Developer Access and Platform Inclusivity
Many developers and researchers use macOS as their primary OS. Supporting tpm2-tools would remove the need for Linux VMs, Docker, or WSL, reducing overhead and attracting more contributors and testers.

2. Streamlined Cross-Platform Prototyping
Prototype code and demos would run natively on both Linux and macOS, improving development velocity and minimizing environment-specific bugs during rapid prototyping.

3. Easier Onboarding and Education
Lowering barriers for students, enterprise engineers, and researchers (who may be Mac-centric) will make experimentation and integration easier.

4. Enhances CI/CD and Automated Testing
Support for macOS would help diversify your integration testing matrix, catching edge cases across different system libraries and OS behaviors, and increasing overall software robustness.

5. Foundation for Future Production Use-Cases
As Apple Silicon spreads to server and edge devices, macOS support (even if not production-targeted) could help seed future use-cases and research, particularly in regulated or privacy-focused industries.

6. Security Research and Tooling Ecosystem Growth
TPM2 tools enable key management, attestation, and trusted execution flows. Adding support in macOS could inspire other open source and security tool integrations, strengthening the overall trusted computing ecosystem.

7. Reduced Context Switching
Developers who primarily work on macOS wouldn’t need to dual-boot or constantly shift to Linux just for TPM workloads, making daily workflows more efficient.

# Build TPM2 pre-reqs and TPM2 tools
1. Open the ystem-setup-mac-apple.sh script and run the build one by one 
2. Make sure your terminal has the following variables
   export PREFIX="/opt/homebrew"
   export TPM2TOOLS_TCTI="libtss2-tcti-swtpm.dylib:host=127.0.0.1,port=${SWTPM_PORT}"
   export DYLD_LIBRARY_PATH="${PREFIX}/lib:${DYLD_LIBRARY_PATH:-}"

#### How to test Prototype?
1. For python tests, create venv and install requirements.txt ( make sure TPM2TOOLS_TCTI and DYLD_LIBRARY_PATH are set)
2. Refer [README_demo.md](https://github.com/lfedgeai/AegisEdgeAI/tree/main/zero-trust/README_demo.md)
