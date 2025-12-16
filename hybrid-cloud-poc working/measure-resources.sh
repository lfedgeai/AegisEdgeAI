#!/bin/bash
# Resource Measurement Script for Sizing/Dimensioning Report
# Measures CPU and Memory usage of all TLM components

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

OUTPUT_FILE="/tmp/tlm-sizing-report-$(date +%Y%m%d-%H%M%S).txt"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Trust Level Management (TLM) - Resource Sizing Report        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to get process stats
get_process_stats() {
    local process_name=$1
    local grep_pattern=$2
    
    echo "=== $process_name ===" | tee -a "$OUTPUT_FILE"
    
    # Get all matching processes
    ps aux | grep -E "$grep_pattern" | grep -v grep | while read line; do
        user=$(echo $line | awk '{print $1}')
        pid=$(echo $line | awk '{print $2}')
        cpu=$(echo $line | awk '{print $3}')
        mem=$(echo $line | awk '{print $4}')
        vsz=$(echo $line | awk '{print $5}')
        rss=$(echo $line | awk '{print $6}')
        
        # Convert RSS from KB to MB
        rss_mb=$(echo "scale=2; $rss / 1024" | bc)
        vsz_mb=$(echo "scale=2; $vsz / 1024" | bc)
        
        echo "  PID: $pid" | tee -a "$OUTPUT_FILE"
        echo "  CPU: ${cpu}%" | tee -a "$OUTPUT_FILE"
        echo "  Memory: ${mem}%" | tee -a "$OUTPUT_FILE"
        echo "  RSS (Actual RAM): ${rss_mb} MB" | tee -a "$OUTPUT_FILE"
        echo "  VSZ (Virtual): ${vsz_mb} MB" | tee -a "$OUTPUT_FILE"
        echo "" | tee -a "$OUTPUT_FILE"
    done
}

# Function to calculate total for a component
calculate_total() {
    local grep_pattern=$1
    local component_name=$2
    
    # Sum up RSS (actual memory) for all processes
    total_rss=$(ps aux | grep -E "$grep_pattern" | grep -v grep | awk '{sum+=$6} END {print sum}')
    total_rss_mb=$(echo "scale=2; $total_rss / 1024" | bc)
    
    # Average CPU
    avg_cpu=$(ps aux | grep -E "$grep_pattern" | grep -v grep | awk '{sum+=$3; count++} END {if(count>0) print sum/count; else print 0}')
    
    # Count processes
    proc_count=$(ps aux | grep -E "$grep_pattern" | grep -v grep | wc -l)
    
    echo "  Total Processes: $proc_count" | tee -a "$OUTPUT_FILE"
    echo "  Total Memory (RSS): ${total_rss_mb} MB" | tee -a "$OUTPUT_FILE"
    echo "  Average CPU: ${avg_cpu}%" | tee -a "$OUTPUT_FILE"
    echo "" | tee -a "$OUTPUT_FILE"
}

# Header
echo "Trust Level Management (TLM) Components - Resource Usage" | tee "$OUTPUT_FILE"
echo "Generated: $(date)" | tee -a "$OUTPUT_FILE"
echo "Host: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "═══════════════════════════════════════════════════════════════" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# 1. Keylime Verifier
echo -e "${YELLOW}1. Keylime Verifier${NC}"
get_process_stats "Keylime Verifier" "keylime.cmd.verifier"
calculate_total "keylime.cmd.verifier" "Keylime Verifier"

# 2. Keylime Registrar
echo -e "${YELLOW}2. Keylime Registrar${NC}"
get_process_stats "Keylime Registrar" "keylime.cmd.registrar"
calculate_total "keylime.cmd.registrar" "Keylime Registrar"

# 3. rust-keylime Agent
echo -e "${YELLOW}3. rust-keylime Agent${NC}"
get_process_stats "rust-keylime Agent" "keylime_agent"
calculate_total "keylime_agent" "rust-keylime Agent"

# 4. SPIRE Server
echo -e "${YELLOW}4. SPIRE Server${NC}"
get_process_stats "SPIRE Server" "spire-server"
calculate_total "spire-server" "SPIRE Server"

# 5. SPIRE Agent
echo -e "${YELLOW}5. SPIRE Agent${NC}"
get_process_stats "SPIRE Agent" "spire-agent"
calculate_total "spire-agent" "SPIRE Agent"

# 6. TPM Plugin Server
echo -e "${YELLOW}6. TPM Plugin Server${NC}"
get_process_stats "TPM Plugin Server" "tpm_plugin_server"
calculate_total "tpm_plugin_server" "TPM Plugin Server"

# 7. Mobile Sensor Service (if running)
echo -e "${YELLOW}7. Mobile Location Verification Service${NC}"
get_process_stats "Mobile Sensor Service" "mobile_sensor_service"
calculate_total "mobile_sensor_service" "Mobile Sensor Service"

# Overall Summary
echo "═══════════════════════════════════════════════════════════════" | tee -a "$OUTPUT_FILE"
echo "OVERALL SUMMARY" | tee -a "$OUTPUT_FILE"
echo "═══════════════════════════════════════════════════════════════" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Calculate grand totals
total_all_rss=$(ps aux | grep -E "keylime|spire|tpm_plugin" | grep -v grep | awk '{sum+=$6} END {print sum}')
total_all_rss_mb=$(echo "scale=2; $total_all_rss / 1024" | bc)
total_all_cpu=$(ps aux | grep -E "keylime|spire|tpm_plugin" | grep -v grep | awk '{sum+=$3} END {print sum}')
total_processes=$(ps aux | grep -E "keylime|spire|tpm_plugin" | grep -v grep | wc -l)

echo "Total TLM Processes: $total_processes" | tee -a "$OUTPUT_FILE"
echo "Total Memory Usage: ${total_all_rss_mb} MB" | tee -a "$OUTPUT_FILE"
echo "Total CPU Usage: ${total_all_cpu}%" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# System info
echo "═══════════════════════════════════════════════════════════════" | tee -a "$OUTPUT_FILE"
echo "SYSTEM INFORMATION" | tee -a "$OUTPUT_FILE"
echo "═══════════════════════════════════════════════════════════════" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

total_mem=$(free -m | awk 'NR==2{print $2}')
used_mem=$(free -m | awk 'NR==2{print $3}')
free_mem=$(free -m | awk 'NR==2{print $4}')
cpu_count=$(nproc)

echo "Total System Memory: ${total_mem} MB" | tee -a "$OUTPUT_FILE"
echo "Used System Memory: ${used_mem} MB" | tee -a "$OUTPUT_FILE"
echo "Free System Memory: ${free_mem} MB" | tee -a "$OUTPUT_FILE"
echo "CPU Cores: ${cpu_count}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Percentage of system resources used by TLM
tlm_mem_percent=$(echo "scale=2; ($total_all_rss_mb / $total_mem) * 100" | bc)
echo "TLM Memory Usage: ${tlm_mem_percent}% of total system memory" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Report saved to: $OUTPUT_FILE${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "View report: cat $OUTPUT_FILE"
echo "Or: less $OUTPUT_FILE"
