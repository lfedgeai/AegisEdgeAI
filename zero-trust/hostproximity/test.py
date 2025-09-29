import ctypes

lib = ctypes.CDLL("./hostproximity.so")

lib.MeasureLatency.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.MeasureLatency.restype = ctypes.c_double
# replace with ip address of an actual VM
latency = lib.MeasureLatency(b"10.0.0.101", b"22")
print(f"Latency: {latency} ms")
lib.FindClosestVM.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
lib.FindClosestVM.restype = ctypes.c_char_p

closest = lib.FindClosestVM(b"10.0.0.101,10.0.0.102,10.0.0.103", b"22")
print(f"Closest VM: {closest.decode()}")
