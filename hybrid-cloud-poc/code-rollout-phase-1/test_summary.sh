#!/bin/bash
echo "=========================================="
echo "Phase 1: Complete Test Summary"
echo "=========================================="
echo ""
echo "Feature Flag Tests:"
cd spire && go test -v ./pkg/common/fflag/... 2>&1 | grep -E "(PASS|FAIL|ok)" | tail -5
echo ""
echo "Unified Identity Tests:"
cd spire && go test -v ./pkg/server/unifiedidentity/... 2>&1 | grep -E "(PASS|FAIL|ok)" | tail -5
echo ""
echo "=========================================="
