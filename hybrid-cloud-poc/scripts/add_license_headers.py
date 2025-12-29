#!/usr/bin/env python3
"""
Add Apache 2.0 license headers to source files.

This script audits and adds Apache 2.0 license headers to:
- .go files (Go)
- .rs files (Rust)
- .py files (Python)
- .sh files (Shell)

Usage:
    python3 add_license_headers.py [--check] [--fix] [--exclude-dir DIR]
"""

import os
import sys
import argparse
import re
from pathlib import Path
from typing import List, Tuple, Optional

# Apache 2.0 License Header Template
APACHE_HEADER = """Copyright 2025 AegisSovereignAI Authors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License."""

# Comment styles for different file types
COMMENT_STYLES = {
    '.go': '//',
    '.rs': '//',
    '.py': '#',
    '.sh': '#',
}

# Directories to exclude (vendor, generated code, etc.)
EXCLUDE_DIRS = {
    'vendor', 'node_modules', '.git', '.build', 'target', '__pycache__',
    '.pytest_cache', 'dist', 'build', '.venv', 'venv', 'go-spiffe',
    'spire', 'keylime', 'rust-keylime', 'spire-api-sdk',  # Upstream repos
}

# Files to exclude (generated, third-party, etc.)
EXCLUDE_FILES = {
    '*.pb.go', '*.pb.rs', '*.generated.go', '*.generated.rs',
}

# Patterns that indicate a file already has a license header
LICENSE_PATTERNS = [
    r'Copyright.*AegisSovereignAI',
    r'Copyright.*Apache',
    r'Licensed under the Apache License',
    r'SPDX-License-Identifier.*Apache',
]


def has_license_header(content: str) -> bool:
    """Check if file already has a license header."""
    # Check first 50 lines for license patterns
    lines = content.split('\n')[:50]
    header_text = '\n'.join(lines)
    return any(re.search(pattern, header_text, re.IGNORECASE) for pattern in LICENSE_PATTERNS)


def format_header(file_ext: str, header_text: str) -> str:
    """Format header with appropriate comment style."""
    comment_prefix = COMMENT_STYLES.get(file_ext, '#')
    lines = header_text.strip().split('\n')
    formatted = []
    for line in lines:
        if line.strip():
            formatted.append(f"{comment_prefix} {line}")
        else:
            formatted.append(comment_prefix)
    return '\n'.join(formatted) + '\n'


def should_process_file(file_path: Path) -> bool:
    """Check if file should be processed."""
    # Check exclude directories
    for part in file_path.parts:
        if part in EXCLUDE_DIRS:
            return False

    # Check exclude patterns
    for pattern in EXCLUDE_FILES:
        if file_path.match(pattern):
            return False

    return True


def process_file(file_path: Path, check_only: bool = False) -> Tuple[bool, Optional[str]]:
    """
    Process a single file.
    Returns: (needs_header, error_message)
    """
    if not should_process_file(file_path):
        return False, None

    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
    except Exception as e:
        return False, f"Error reading file: {e}"

    # Skip empty files
    if not content.strip():
        return False, None

    # Check if already has header
    if has_license_header(content):
        return False, None

    # File needs header
    if check_only:
        return True, None

    # Add header
    file_ext = file_path.suffix
    header = format_header(file_ext, APACHE_HEADER)

    # Handle shebang lines
    lines = content.split('\n')
    insert_pos = 0
    if lines and lines[0].startswith('#!'):
        insert_pos = 1
        # Add blank line after shebang if not present
        if len(lines) > 1 and lines[1].strip():
            header = '\n' + header

    # Insert header
    new_lines = lines[:insert_pos] + [header] + lines[insert_pos:]
    new_content = '\n'.join(new_lines)

    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        return True, None
    except Exception as e:
        return True, f"Error writing file: {e}"


def find_source_files(root_dir: Path) -> List[Path]:
    """Find all source files to process."""
    files = []
    for ext in COMMENT_STYLES.keys():
        for file_path in root_dir.rglob(f'*{ext}'):
            if file_path.is_file() and should_process_file(file_path):
                files.append(file_path)
    return sorted(files)


def main():
    parser = argparse.ArgumentParser(
        description='Add Apache 2.0 license headers to source files'
    )
    parser.add_argument(
        '--check',
        action='store_true',
        help='Check only, do not modify files'
    )
    parser.add_argument(
        '--fix',
        action='store_true',
        help='Add headers to files that need them'
    )
    parser.add_argument(
        '--exclude-dir',
        action='append',
        default=[],
        help='Additional directories to exclude'
    )
    parser.add_argument(
        '--root',
        type=str,
        default='hybrid-cloud-poc',
        help='Root directory to process (default: hybrid-cloud-poc)'
    )

    args = parser.parse_args()

    # Add custom exclude dirs
    EXCLUDE_DIRS.update(args.exclude_dir)

    root_dir = Path(args.root)
    if not root_dir.exists():
        print(f"Error: Root directory does not exist: {root_dir}", file=sys.stderr)
        sys.exit(1)

    files = find_source_files(root_dir)
    print(f"Found {len(files)} source files to check")

    needs_header = []
    errors = []

    for file_path in files:
        needs, error = process_file(file_path, check_only=args.check or not args.fix)
        if error:
            errors.append((file_path, error))
        elif needs:
            needs_header.append(file_path)

    # Report results
    if errors:
        print("\nErrors:", file=sys.stderr)
        for file_path, error in errors:
            print(f"  {file_path}: {error}", file=sys.stderr)

    if needs_header:
        if args.check:
            print(f"\n❌ {len(needs_header)} files missing license headers:")
            for file_path in needs_header:
                print(f"  {file_path}")
            sys.exit(1)
        else:
            print(f"\n✅ Added headers to {len(needs_header)} files:")
            for file_path in needs_header:
                print(f"  {file_path}")
    else:
        print("\n✅ All files have license headers")

    if errors:
        sys.exit(1)


if __name__ == '__main__':
    main()
