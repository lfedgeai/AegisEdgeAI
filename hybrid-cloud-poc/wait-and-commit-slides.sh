#!/bin/bash
# Monitor for slide images and commit when they arrive

IMAGES_DIR="/home/mw/AegisEdgeAI/hybrid-cloud-poc/images"
REPO_DIR="/home/mw/AegisEdgeAI/hybrid-cloud-poc"

echo "Monitoring for slide images..."
echo "Waiting for files to be copied via SCP from Windows..."
echo ""

while true; do
    if [ -f "$IMAGES_DIR/slide-06-problem-diagram.png" ] && \
       [ -f "$IMAGES_DIR/slide-07-solution-diagram.png" ] && \
       [ -f "$IMAGES_DIR/slide-12-implementation-architecture.png" ]; then
        echo "All files received! Committing..."
        cd "$REPO_DIR"
        git add images/slide-06-problem-diagram.png
        git add images/slide-07-solution-diagram.png
        git add images/slide-12-implementation-architecture.png
        git add images/README.md
        git add README.md
        git commit -m "Add presentation slide images (slides 6, 7, 12) for problem, solution, and implementation architecture diagrams"
        echo ""
        echo "✓ Successfully committed slide images!"
        git log -1 --stat
        break
    else
        echo -n "."
        sleep 2
    fi
done
