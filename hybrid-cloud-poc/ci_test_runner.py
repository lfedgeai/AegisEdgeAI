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
Enhanced with step parsing, timeout detection, and GitHub Actions integration.
"""
import sys
import subprocess
import time
import re
import threading
import os
from pathlib import Path
from datetime import datetime

class Colors:
    """ANSI color codes for terminal output"""
    GREEN = '\033[0;32m'
    RED = '\033[0;31m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    BLUE = '\033[0;34m'
    BOLD = '\033[1m'
    NC = '\033[0m'  # No Color

    @classmethod
    def disable(cls):
        """Disable colors for CI environments"""
        cls.GREEN = cls.RED = cls.YELLOW = cls.CYAN = cls.BLUE = cls.BOLD = cls.NC = ''

class TestRunner:
    def __init__(self, args=None, no_color=False, max_runtime_minutes=60, no_output_timeout_minutes=15):
        self.args = args or []
        self.start_time = None
        self.end_time = None
        self.exit_code = None
        self.log_dir = None
        self.errors = []
        self.warnings = []
        self.step_results = []  # Track step success/failure
        self.step_hierarchy = {}  # Track step hierarchy (main step -> sub-steps)
        self.step_status_by_desc = {}  # Track final status by step description
        self.has_unrecovered_step_failure = False
        self.failed_step = None
        self.process = None
        self.last_output_time = None
        self.timeout_detected = False
        self.timeout_reason = None
        self.max_runtime_seconds = max_runtime_minutes * 60
        self.no_output_timeout_seconds = no_output_timeout_minutes * 60
        
        # GitHub Actions detection
        self.github_actions = os.environ.get('GITHUB_ACTIONS') == 'true'
        
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

    def parse_step_info(self, line):
        """Parse [STEP_SUCCESS] or [STEP_FAILURE] messages to extract step information"""
        # Match: [STEP_SUCCESS] Step X.Y: Description - Details
        # or: [STEP_SUCCESS] Description
        step_success_match = re.search(r'\[STEP_SUCCESS\]\s*(?:Step\s+(\d+(?:\.\d+)?):\s*)?(.+?)(?:\s*-\s*(.+))?$', line)
        if step_success_match:
            step_num = step_success_match.group(1)
            description = step_success_match.group(2).strip()
            details = step_success_match.group(3).strip() if step_success_match.group(3) else ''
            
            # Determine if this is a sub-step
            is_substep = step_num and '.' in step_num if step_num else False
            main_step = step_num.split('.')[0] if step_num and '.' in step_num else step_num
            
            step_info = {
                'status': 'SUCCESS',
                'step_number': step_num,
                'description': description,
                'details': details,
                'is_substep': is_substep,
                'main_step': main_step,
                'timestamp': datetime.now()
            }
            self.step_results.append(step_info)
            self.step_status_by_desc[description] = 'SUCCESS'
            
            # Track hierarchy
            if step_info['main_step'] is not None:
                main_key = step_info['main_step']
                if main_key not in self.step_hierarchy:
                    self.step_hierarchy[main_key] = []
                if step_info['is_substep']:
                    self.step_hierarchy[main_key].append(step_info)
            
            return True
        
        # Match: [STEP_FAILURE] Step X.Y: Description - Details
        step_failure_match = re.search(r'\[STEP_FAILURE\]\s*(?:Step\s+(\d+(?:\.\d+)?):\s*)?(.+?)(?:\s*-\s*(.+))?$', line)
        if step_failure_match:
            step_num = step_failure_match.group(1)
            description = step_failure_match.group(2).strip()
            details = step_failure_match.group(3).strip() if step_failure_match.group(3) else ''
            
            is_substep = step_num and '.' in step_num if step_num else False
            main_step = step_num.split('.')[0] if step_num and '.' in step_num else step_num
            
            step_info = {
                'status': 'FAILURE',
                'step_number': step_num,
                'description': description,
                'details': details,
                'is_substep': is_substep,
                'main_step': main_step,
                'timestamp': datetime.now()
            }
            self.step_results.append(step_info)
            self.step_status_by_desc[description] = 'FAILURE'
            
            # Track hierarchy
            if step_info['main_step'] is not None:
                main_key = step_info['main_step']
                if main_key not in self.step_hierarchy:
                    self.step_hierarchy[main_key] = []
                if step_info['is_substep']:
                    self.step_hierarchy[main_key].append(step_info)
            
            # Track first failed step
            if not self.failed_step:
                self.failed_step = {
                    'description': description,
                    'details': details,
                    'step_number': step_num
                }
            
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

    def github_annotation(self, level, message):
        """Emit GitHub Actions annotation"""
        if self.github_actions:
            print(f"::{level}::{message}")

    def write_github_summary(self):
        """Write GitHub Actions job summary"""
        if not self.github_actions:
            return
        
        summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
        if not summary_path:
            return
        
        try:
            with open(summary_path, 'w') as f:
                f.write("# Test Run Summary\n\n")
                duration = (self.end_time - self.start_time).total_seconds() if self.end_time else 0
                f.write(f"**Duration:** {duration:.1f} seconds\n")
                f.write(f"**Exit Code:** {self.exit_code}\n\n")
                
                if self.log_dir:
                    f.write(f"**Logs:** `{self.log_dir}`\n\n")
                
                if self.step_results:
                    f.write("## Step Results\n\n")
                    for step in self.step_results:
                        status_icon = "✓" if step['status'] == 'SUCCESS' else "✗"
                        f.write(f"{status_icon} {step.get('description', 'Unknown')}\n")
                        if step.get('details'):
                            f.write(f"   - {step['details']}\n")
                
                if self.errors:
                    f.write("\n## Errors\n\n")
                    for error in self.errors[:10]:
                        f.write(f"- {error}\n")
                
                if self.warnings:
                    f.write("\n## Warnings\n\n")
                    for warning in self.warnings[:10]:
                        f.write(f"- {warning}\n")
        except Exception:
            pass  # Ignore errors writing summary

    def github_set_output(self, name, value):
        """Set GitHub Actions output variable"""
        if self.github_actions:
            output_file = os.environ.get('GITHUB_OUTPUT')
            if output_file:
                try:
                    with open(output_file, 'a') as f:
                        f.write(f"{name}={value}\n")
                except Exception:
                    pass

    def print_header(self):
        """Print CI run header"""
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"{Colors.BOLD}CI Test Runner - Unified Identity Integration Tests{Colors.NC}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Command: ./test_integration.sh {' '.join(self.args)}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print()

    def _timeout_monitor(self):
        """Background thread to monitor for timeouts"""
        while self.process and self.process.poll() is None:
            if self.timeout_detected:
                break
            
            elapsed = (datetime.now() - self.start_time).total_seconds()
            
            # Check max runtime
            if elapsed > self.max_runtime_seconds:
                self.timeout_detected = True
                self.timeout_reason = f"Maximum runtime exceeded ({self.max_runtime_seconds}s)"
                self.exit_code = 124
                if self.process:
                    self.process.terminate()
                break
            
            # Check no-output timeout
            if self.last_output_time:
                no_output_elapsed = (datetime.now() - self.last_output_time).total_seconds()
                if no_output_elapsed > self.no_output_timeout_seconds:
                    self.timeout_detected = True
                    self.timeout_reason = f"No output for {self.no_output_timeout_seconds}s (possible stuck process)"
                    self.exit_code = 124
                    if self.process:
                        self.process.terminate()
                    break
            
            time.sleep(5)  # Check every 5 seconds

    def print_summary(self):
        """Print test run summary"""
        duration = (self.end_time - self.start_time).total_seconds() if self.end_time else 0

        print()
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"{Colors.BOLD}Test Run Summary{Colors.NC}")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        print(f"Duration: {duration:.1f} seconds")
        print(f"Exit Code: {self.exit_code}")
        
        if self.timeout_detected:
            print(f"{Colors.RED}Timeout: {self.timeout_reason}{Colors.NC}")

        if self.log_dir:
            print(f"Logs: {self.log_dir}")

        if self.warnings:
            print(f"\n{Colors.YELLOW}Warnings ({len(self.warnings)}):{Colors.NC}")
            for warning in self.warnings[:5]:  # Show first 5
                print(f"  • {warning}")
            if len(self.warnings) > 5:
                print(f"  ... and {len(self.warnings) - 5} more")

        # Display step results hierarchically
        if self.step_results:
            print(f"\n{Colors.BOLD}Step Results:{Colors.NC}")
            # Group by main step
            main_steps = {}
            for step in self.step_results:
                main_key = step.get('main_step') or step.get('step_number', 'unknown')
                if main_key not in main_steps:
                    main_steps[main_key] = []
                main_steps[main_key].append(step)
            
            # Display hierarchically
            for main_key in sorted(main_steps.keys(), key=lambda x: (x or '').replace('.', ' ')):
                steps = main_steps[main_key]
                # Find main step (non-substep)
                main_step = next((s for s in steps if not s.get('is_substep')), steps[0])
                status_icon = f"{Colors.GREEN}✓{Colors.NC}" if main_step['status'] == 'SUCCESS' else f"{Colors.RED}✗{Colors.NC}"
                print(f"  {status_icon} {main_step.get('description', 'Unknown')}")
                
                # Show sub-steps
                substeps = [s for s in steps if s.get('is_substep')]
                for substep in sorted(substeps, key=lambda x: x.get('step_number', '')):
                    sub_status_icon = f"{Colors.GREEN}✓{Colors.NC}" if substep['status'] == 'SUCCESS' else f"{Colors.RED}✗{Colors.NC}"
                    print(f"    {sub_status_icon} {substep.get('description', 'Unknown')}")
                    if substep.get('details'):
                        print(f"      - {substep['details']}")

        if self.errors or self.has_unrecovered_step_failure:
            # Filter errors: exclude step failures that later succeeded (if test passed)
            filtered_errors = []
            recovered_steps = []
            for step_info in self.step_results:
                if step_info.get('status') == 'FAILURE':
                    desc = step_info.get('description', '')
                    details = step_info.get('details', '')
                    full_msg = f"{desc}" + (f" - {details}" if details else "")
                    
                    # Check if this step later succeeded
                    if desc in self.step_status_by_desc and self.step_status_by_desc[desc] == 'SUCCESS':
                        recovered_steps.append(full_msg)
                    else:
                        # Only add to filtered_errors if not already present
                        if full_msg not in filtered_errors:
                            filtered_errors.append(full_msg)
            
            # Add other non-step errors
            for error in self.errors:
                is_step_failure_error = False
                for step_desc in self.step_status_by_desc.keys():
                    if step_desc in error or error in step_desc:
                        is_step_failure_error = True
                        break
                if not is_step_failure_error and error not in filtered_errors:
                    filtered_errors.append(error)
            
            if recovered_steps:
                print(f"\n{Colors.YELLOW}Recovered Steps ({len(recovered_steps)}):{Colors.NC}")
                for step in recovered_steps:
                    print(f"  • {step}")
                    self.github_annotation('warning', f"Recovered: {step}")
            
            if filtered_errors:
                print(f"\n{Colors.RED}Errors ({len(filtered_errors)}):{Colors.NC}")
                for error in filtered_errors[:10]:  # Show first 10
                    print(f"  • {error}")
                    self.github_annotation('error', error)
                if len(filtered_errors) > 10:
                    print(f"  ... and {len(filtered_errors) - 10} more")

        print(f"\n{Colors.BOLD}{'='*80}{Colors.NC}")
        if self.exit_code == 0 and not self.has_unrecovered_step_failure:
            print(f"{Colors.GREEN}{Colors.BOLD}✓ TESTS PASSED{Colors.NC}")
        else:
            print(f"{Colors.RED}{Colors.BOLD}✗ TESTS FAILED - Step failure detected{Colors.NC}")
            if self.failed_step:
                print(f"\n{Colors.YELLOW}First Failed Step:{Colors.NC}")
                print(f"  {self.failed_step.get('description', 'Unknown')}")
                if self.failed_step.get('details'):
                    print(f"  Reason: {self.failed_step['details']}")
            if self.log_dir:
                print(f"\n{Colors.YELLOW}Check logs for details:{Colors.NC}")
                print(f"  master.log: {self.log_dir}/master.log")
        print(f"{Colors.BOLD}{'='*80}{Colors.NC}")
        
        # Write GitHub summary
        self.write_github_summary()
        
        # Set GitHub outputs
        self.github_set_output('exit_code', str(self.exit_code))
        self.github_set_output('test_status', 'passed' if self.exit_code == 0 and not self.has_unrecovered_step_failure else 'failed')
        if self.failed_step:
            self.github_set_output('failed_step', self.failed_step.get('description', ''))
        if self.log_dir:
            self.github_set_output('log_dir', self.log_dir)
        self.github_set_output('timeout_detected', 'true' if self.timeout_detected else 'false')
        if self.timeout_reason:
            self.github_set_output('timeout_reason', self.timeout_reason)

    def run(self):
        """Run the integration tests"""
        self.print_header()
        self.start_time = datetime.now()
        self.last_output_time = self.start_time

        script_path = Path(__file__).parent / 'test_integration.sh'
        if not script_path.exists():
            print(f"{Colors.RED}Error: test_integration.sh not found at {script_path}{Colors.NC}")
            return 1

        cmd = [str(script_path)] + self.args

        try:
            # Run test_integration.sh with real-time output streaming
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                bufsize=1
            )

            # Start timeout monitor thread
            timeout_thread = threading.Thread(target=self._timeout_monitor, daemon=True)
            timeout_thread.start()

            # Stream output line by line
            for line in self.process.stdout:
                # Print to stdout for real-time monitoring
                print(line, end='')
                self.last_output_time = datetime.now()

                # Extract log directory
                self.extract_log_dir(line)

                # Parse step success/failure messages
                self.parse_step_info(line)

                # Detect errors and warnings
                self.detect_error(line)
                self.detect_warning(line)

            # Wait for completion
            self.process.wait()
            self.exit_code = self.process.returncode
            
            # Check for unrecovered step failures - these should cause test to fail
            # even if the script exited with 0
            for step_info in self.step_results:
                if step_info.get('status') == 'FAILURE':
                    desc = step_info.get('description', '')
                    # Check if this step later succeeded
                    if desc not in self.step_status_by_desc or self.step_status_by_desc[desc] != 'SUCCESS':
                        # Step failed and didn't recover - this should fail the test
                        self.has_unrecovered_step_failure = True
                        break
            
            # If any step failed without recovery, fail the test (even if script exited with 0)
            if self.has_unrecovered_step_failure and self.exit_code == 0:
                self.exit_code = 1
                print(f"\n{Colors.RED}{Colors.BOLD}⚠ TEST FAILED: Step failure detected (script may not have halted properly){Colors.NC}")

        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.NC}")
            if self.process:
                self.process.terminate()
                self.process.wait()
            self.exit_code = 130
        except Exception as e:
            print(f"{Colors.RED}Error running tests: {e}{Colors.NC}")
            self.exit_code = 1

        self.end_time = datetime.now()

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

  # Configure timeouts (detect stuck processes)
  ./ci_test_runner.py --max-runtime 120 --no-output-timeout 20

  # Pass through arguments to test_integration.sh
  ./ci_test_runner.py -- --no-pause --no-build
        """
    )

    parser.add_argument('--no-color', action='store_true',
                        help='Disable color output (for CI)')
    parser.add_argument('--max-runtime', type=int, default=60, metavar='MINUTES',
                        help='Maximum total runtime in minutes before timeout (default: 60)')
    parser.add_argument('--no-output-timeout', type=int, default=15, metavar='MINUTES',
                        help='Maximum time without output before timeout in minutes (default: 15)')
    parser.add_argument('test_args', nargs='*',
                        help='Arguments to pass to test_integration.sh (use -- to separate)')

    # Parse only known args, let the rest pass through
    args, unknown = parser.parse_known_args()

    # Combine test_args and unknown args
    all_test_args = args.test_args + unknown

    # Add --no-pause by default for CI usage (unless already present)
    if '--no-pause' not in all_test_args and '--pause' not in ' '.join(all_test_args):
        all_test_args.append('--no-pause')

    runner = TestRunner(
        args=all_test_args,
        no_color=args.no_color,
        max_runtime_minutes=args.max_runtime,
        no_output_timeout_minutes=args.no_output_timeout
    )
    exit_code = runner.run()
    sys.exit(exit_code)

if __name__ == '__main__':
    main()
