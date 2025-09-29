package main

/*
#include <stdint.h>
*/
import "C"

import (
	"net"
	"strings"
	"time"
)

//export MeasureLatency
func MeasureLatency(ip *C.char, port *C.char) C.double {
	goIP := C.GoString(ip)
	goPort := C.GoString(port)

	start := time.Now()
	conn, err := net.DialTimeout("tcp", net.JoinHostPort(goIP, goPort), 2*time.Second)
	if err != nil {
		return -1 // return -1 on error
	}
	_ = conn.Close()
	return C.double(time.Since(start).Milliseconds())
}

//export FindClosestVM
func FindClosestVM(ipList *C.char, port *C.char) *C.char {
	goIPs := C.GoString(ipList)
	ips := splitAndTrim(goIPs)
	goPort := C.GoString(port)

	var bestIP string
	var bestLatency time.Duration

	for _, ip := range ips {
		latency, err := net.DialTimeout("tcp", net.JoinHostPort(ip, goPort), 2*time.Second)
		if err != nil {
			continue
		}
		conn, _ := net.DialTimeout("tcp", net.JoinHostPort(ip, goPort), 2*time.Second)
		if conn != nil {
			conn.Close()
		}
		if bestIP == "" || latency < bestLatency {
			bestIP = ip
			bestLatency = latency
		}
	}

	if bestIP == "" {
		return C.CString("")
	}
	return C.CString(bestIP)
}

func splitAndTrim(s string) []string {
	raw := []string{}
	for _, part := range strings.Split(s, ",") {
		trimmed := strings.TrimSpace(part)
		if trimmed != "" {
			raw = append(raw, trimmed)
		}
	}
	return raw
}

// Required main for c-shared build
func main() {}
