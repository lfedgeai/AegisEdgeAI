#!/bin/bash
# Auto-commit slide images once they arrive

cd /home/mw/AegisEdgeAI/hybrid-cloud-poc/images

if [ -f slide-06-problem-diagram.png ] && \
   [ -f slide-07-solution-diagram.png ] && \
   [ -f slide-12-implementation-architecture.png ]; then
    echo "All slide images found! Committing..."
    cd ..
    git add images/slide-06-problem-diagram.png
    git add images/slide-07-solution-diagram.png
    git add images/slide-12-implementation-architecture.png
    git add images/README.md
    git add README.md
    git commit -m "Add presentation slide images (6, 7, 12) for problem, solution, and implementation architecture"
    echo "Committed successfully!"
    git status
else
    echo "Waiting for slide images..."
    echo "Missing files:"
    [ ! -f slide-06-problem-diagram.png ] && echo "  - slide-06-problem-diagram.png"
    [ ! -f slide-07-solution-diagram.png ] && echo "  - slide-07-solution-diagram.png"
    [ ! -f slide-12-implementation-architecture.png ] && echo "  - slide-12-implementation-architecture.png"
fi
