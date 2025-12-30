#!/usr/bin/env python3

# Copyright 2025 AegisSovereignAI Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
CI Test Runner for Unified Identity Integration Tests
Runs test_integration.sh with real-time monitoring and structured CI output.
"""
import sys
import subprocess
import time
import re
from pathlib import Path
from datetime import datetime

class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    BOLD = '\033[1m'
    NC = '\033[0m'  # No Color

    @classmethod
    def disable(cls):
        """Disable colors for CI environments"""
        cls.GREEN = cls.RED = cls.YELLOW = cls.CYAN = cls.BOLD = cls.NC = ''

class TestRunner:
    def __init__(self, args=None, no_color=False):
        self.args = args or []
        self.start_time = None
        self.end_time = None
        self.exit_code = None
        self.log_dir = None
        self.errors = []
        self.warnings = []
        self.service_logs = {
            'SPIRE Server': '/tmp/spire-server.log',
            'SPIRE Agent': '/tmp/spire-agent.log',
            'Keylime Verifier': '/tmp/keylime-verifier.log',
            'Keylime Registrar': '/tmp/keylime-registrar.log',
            'Keylime Agent': '/tmp/keylime-agent.log',
            'Envoy Proxy': '/opt/envoy/logs/envoy.log',
            'Mobile Sensor': '/tmp/mobile-sensor.log',
            'mTLS Server': '/tmp/mtls-server.log',
            'mTLS Client': '/tmp/remote_test_mtls_client.log'
        }

        if no_color or not sys.stdout.isatty():
            Colors.disable()

    def extract_log_dir(self, line):
        """Extract log directory from test output"""
        match = re.search(r'Logs will be aggregated in (/tmp/unified_identity_test_\d+)', line)
        if match:
            self.log_dir = match.group(1)
            return True
        return False

    def detect_error(self, line):
        """Detect error patterns in output"""
        # Ignore expected errors
        ignore_patterns = [
            r'may be expected',
            r'tail: cannot open.*No such file',
            r'services weren.*running',
            r'Warning: Not running as root',
        ]
        for pattern in ignore_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                return False

        # Real error patterns
        error_patterns = [
            r'CRITICAL ERROR',
            r'FAILED.*test',
            r'cannot.*connect',
            r'Unable to start',
            r'Exit.*code.*[1-9]',  # Non-zero exit from subprocess
        ]
        for pattern in error_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                self.errors.append(line.strip())
                return True

        # Check for ✗ symbol (failure indicator) but not in cleanup-related messages
        if '✗' in line:
            if any(pattern in line.lower() for pattern in ['cleanup', 'stopping', 'cleaning up']):
                return False  # Ignore cleanup failures
            self.errors.append(line.strip())
            return True

        return False

    def detect_warning(self, line):
        """Detect warning patterns in output"""
        # Ignore very noisy warnings
        ignore_patterns = [
            r'Warning: Not running as root',
            r'may need sudo',
        ]
        for pattern in ignore_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                return False

        warning_patterns = [
            r'WARNING',
            r'⚠.*(?!Agent services cleanup)',  # Warnings except cleanup
        ]
        for pattern in warning_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                self.warnings.append(line.strip())
                return True
        return False

    def print_header(self):
        """Print CI run header"""
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"{Colors.BOLD}CI Test Runner - Unified Identity Integration Tests{Colors.NC}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Command: ./test_integration.sh {' '.join(self.args)}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print()

    def parse_log_files(self):
        """Parse log files after completion to find failure details"""
        if not self.log_dir or not Path(self.log_dir).exists():
            return

        log_files = list(Path(self.log_dir).glob('*.log'))
        if not log_files:
            return

        # Parse master.log first for overall failure
        master_log = Path(self.log_dir) / 'master.log'
        if master_log.exists():
            self._parse_master_log(master_log)

        # Parse individual script logs for specific failures
        for log_file in sorted(log_files):
            if log_file.name != 'master.log':
                self._parse_script_log(log_file)

    def _parse_master_log(self, log_path):
        """Parse master.log to find failure point"""
        try:
            with open(log_path, 'r') as f:
                lines = f.readlines()

            # Find the last error before exit
            for i in range(len(lines) - 1, max(0, len(lines) - 50), -1):
                line = lines[i]
                if any(pattern in line for pattern in ['✗', 'FAILED', 'CRITICAL', 'Error']):
                    # Extract context (5 lines before and after)
                    context_start = max(0, i - 5)
                    context_end = min(len(lines), i + 6)
                    context = ''.join(lines[context_start:context_end])

                    if any(line.strip() == e.split('] ')[-1].strip() for e in self.errors):
                        continue

                    self.errors.append(f"[master.log:{i+1}] {line.strip()}\n{context}")
                    break
        except Exception:
            pass  # Ignore parsing errors

    def _parse_script_log(self, log_path):
        """Parse individual script log to find failure"""
        try:
            with open(log_path, 'r') as f:
                lines = f.readlines()

            # Look for explicit error markers
            for i, line in enumerate(lines):
                if any(pattern in line for pattern in ['✗', 'failed', 'CRITICAL ERROR']):
                    if any(line.strip() == e.split('] ')[-1].strip() for e in self.errors):
                        continue
                    
                    # Extract context (5 lines before and after)
                    context_start = max(0, i - 5)
                    context_end = min(len(lines), i + 6)
                    context = ''.join(lines[context_start:context_end])
                    
                    self.errors.append(f"[{log_path.name}:{i+1}] {line.strip()}\n{context}")
        except Exception:
            pass  # Ignore parsing errors

    def dump_service_logs(self):
        """Dump relevant service logs upon failure"""
        print(f"\n{Colors.BOLD}{Colors.YELLOW}Collecting Diagnostic Service Logs...{Colors.NC}")
        for service, log_path in self.service_logs.items():
            path = Path(log_path)
            if not path.exists():
                continue

            print(f"\n{Colors.BOLD}--- {service} Logs ({log_path}) ---{Colors.NC}")
            try:
                # Get last 50 lines
                result = subprocess.run(['tail', '-n', '50', str(path)], capture_output=True, text=True)
                if result.stdout:
                    print(result.stdout)
                else:
                    print("  (Log file is empty)")
            except Exception as e:
                print(f"  Error reading log: {e}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")

    def print_summary(self):
        """Print test run summary"""
        duration = (self.end_time - self.start_time).total_seconds()

        print()
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"{Colors.BOLD}Test Run Summary{Colors.NC}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"Duration: {duration:.1f} seconds")
        print(f"Exit Code: {self.exit_code}")

        if self.log_dir:
            print(f"Logs: {self.log_dir}")

        if self.warnings:
            print(f"\n{Colors.YELLOW}Warnings ({len(self.warnings)}):{Colors.NC}")
            for warning in self.warnings[:5]:  # Show first 5
                print(f"  • {warning}")
            if len(self.warnings) > 5:
                print(f"  ... and {len(self.warnings) - 5} more")

        if self.errors:
            print(f"\n{Colors.RED}Errors ({len(self.errors)}):{Colors.NC}")
            for error in self.errors[:10]:  # Show first 10
                print(f"  • {error}")
            if len(self.errors) > 10:
                print(f"  ... and {len(self.errors) - 10} more")

        print(f"\n{Colors.BOLD}{'='*80}{Colors.NC}")
        if self.exit_code == 0:
            print(f"{Colors.GREEN}{Colors.BOLD}✓ TESTS PASSED{Colors.NC}")
        else:
            print(f"{Colors.RED}{Colors.BOLD}✗ TESTS FAILED{Colors.NC}")
            if self.log_dir:
                print(f"\n{Colors.YELLOW}Check logs for details:{Colors.NC}")
                print(f"  master.log: {self.log_dir}/master.log")
            
            # Proactively dump service logs in the summary if they haven't been dumped yet
            self.dump_service_logs()
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")

    def run(self):
        """Run the integration tests"""
        self.print_header()
        self.start_time = datetime.now()

        script_path = Path(__file__).parent / 'test_integration.sh'
        if not script_path.exists():
            print(f"{Colors.RED}Error: test_integration.sh not found at {script_path}{Colors.NC}")
            return 1

        cmd = [str(script_path)] + self.args

        try:
            # Run test_integration.sh with real-time output streaming
            process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )

            # Stream output line by line
            for line in process.stdout:
                # Print to stdout for real-time monitoring
                print(line, end='')

                # Extract log directory
                self.extract_log_dir(line)

                # Detect errors and warnings
                self.detect_error(line)
                self.detect_warning(line)

            # Wait for completion
            process.wait()
            self.exit_code = process.returncode

        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.NC}")
            if process:
                process.terminate()
                process.wait()
            self.exit_code = 130
        except Exception as e:
            print(f"{Colors.RED}Error running tests: {e}{Colors.NC}")
            self.exit_code = 1

        self.end_time = datetime.now()

        # Parse log files to extract failure details
        if self.exit_code != 0:
            self.parse_log_files()

        self.print_summary()

        return self.exit_code

def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(
        description='CI Test Runner for Unified Identity Integration Tests',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run full integration test
  ./ci_test_runner.py

  # Run cleanup only
  ./ci_test_runner.py -- --cleanup-only

  # Run with custom hosts (all three components on separate machines)
  ./ci_test_runner.py -- --control-plane-host 10.1.0.11 --agents-host 10.1.0.12 --onprem-host 10.1.0.10

  # Disable colors (for CI)
  ./ci_test_runner.py --no-color

  # Pass through arguments to test_integration.sh
  ./ci_test_runner.py -- --no-pause --no-build
        """
    )

    parser.add_argument('--no-color', action='store_true',
                        help='Disable color output (for CI)')
    parser.add_argument('test_args', nargs='*',
                        help='Arguments to pass to test_integration.sh (use -- to separate)')

    # Parse only known args, let the rest pass through
    args, unknown = parser.parse_known_args()

    # Combine test_args and unknown args
    all_test_args = args.test_args + unknown

    # Add --no-pause by default for CI usage (unless already present)
    if '--no-pause' not in all_test_args and '--pause' not in ' '.join(all_test_args):
        all_test_args.append('--no-pause')

    runner = TestRunner(args=all_test_args, no_color=args.no_color)
    exit_code = runner.run()
    sys.exit(exit_code)

if __name__ == '__main__':
    main()
