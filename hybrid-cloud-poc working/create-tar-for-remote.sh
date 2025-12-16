#!/bin/bash
# Create TAR file with all fixed files ready to copy to remote machine

echo "Creating TAR file with fixed files..."

# Create tar with all 4 corrected files
tar -czf fixed-files.tar.gz \
    keylime/verifier.conf.minimal \
    keylime/keylime/cloud_verifier_tornado.py \
    test_complete.sh \
    python-app-demo/fetch-sovereign-svid-grpc.py \
    READY_TO_COPY_TO_REMOTE.md \
    REMOTE_MACHINE_COMMANDS.md \
    FILE_ANALYSIS_REPORT.md

echo "✓ Created: fixed-files.tar.gz"
echo ""
echo "Files included:"
tar -tzf fixed-files.tar.gz
echo ""
echo "Next steps:"
echo "1. Copy fixed-files.tar.gz to your Linux machine (USB/network)"
echo "2. On Linux: cd ~/dhanush/hybrid-cloud-poc-backup"
echo "3. On Linux: tar -xzf fixed-files.tar.gz"
echo "4. On Linux: Follow instructions in READY_TO_COPY_TO_REMOTE.md"
echo ""
