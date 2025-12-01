#!/bin/bash
# Quick script to commit slide images once they arrive

cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/images

if [ -f slide-06-problem-diagram.png ] && [ -f slide-07-solution-diagram.png ] && [ -f slide-12-implementation-architecture.png ]; then
    cd ..
    git add images/*.png images/README.md README.md
    git commit -m "Add presentation slide images (slides 6, 7, 12) for problem, solution, and implementation architecture diagrams"
    echo "✓ Committed successfully!"
    git log -1 --oneline
else
    echo "Files not all present yet. Missing:"
    [ ! -f images/slide-06-problem-diagram.png ] && echo "  - slide-06-problem-diagram.png"
    [ ! -f images/slide-07-solution-diagram.png ] && echo "  - slide-07-solution-diagram.png"
    [ ! -f images/slide-12-implementation-architecture.png ] && echo "  - slide-12-implementation-architecture.png"
fi
