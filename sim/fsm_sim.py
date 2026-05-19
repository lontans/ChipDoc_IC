"""
CD1624 Behavioral FSM Simulator
ChipDoc Supervisory IC — Jonathan Song, Summer 2026

This is a software behavioral model of the CD1624 fault FSM.
It is not cycle-accurate RTL — it is a design sandbox.
Use it to:
  - Validate state transition logic before writing Verilog
  - Inject fault scenarios and check output behavior
  - Explore latch vs auto-recover policies per fault type
  - Generate reference traces to compare against RTL simulation later

States:
  INIT      — power-on, chip not yet ready, EN_OUT held low
  NORMAL    — all inputs healthy, EN_OUT high, HEALTH high
  FAULT     — one or more faults active, EN_OUT latches low
  RECOVERY  — fault cleared + MR asserted, attempting return to NORMAL

Fault inputs (all active high, asserted by comparators / WD timer):
  oc_a      — overcurrent rail A
  oc_b      — overcurrent rail B
  uv_a      — undervoltage rail A
  ov_a      — overvoltage rail A
  uv_b      — undervoltage rail B
  ov_b      — overvoltage rail B
  ot        — overtemperature
  hb        — heartbeat missing (watchdog timeout)

Control inputs:
  mr        — manual reset, active high in this model (pin is active low externally)

Outputs:
  en_out    — enable output, latches low on FAULT
  health    — deasserts on FAULT
"""


# ─────────────────────────────────────────────
#  Constants
# ─────────────────────────────────────────────

STATES = ["INIT", "NORMAL", "WARN", "FAULT", "RECOVERY"]

FAULT_KEYS = ["oc_a", "oc_b", "uv_a", "ov_a", "uv_b", "ov_b", "ot", "hb"]

# Faults that latch (require MR to recover)
LATCHING_FAULTS = {"ov_a", "ov_b", "hb"}
AUTO_RECOVER_FAULTS = {"oc_a", "oc_b", "uv_a", "uv_b", "ot"}

# Faults that skip WARN and go straight to FAULT
# OV: too dangerous to warn. HB: timeout already implies sustained condition.
IMMEDIATE_FAULTS = {"ov_a", "ov_b", "hb"}

# Number of ticks a warn-eligible fault must persist before escalating to FAULT
WARN_TO_FAULT_CYCLES = 3

# Number of ticks to remain in INIT before transitioning to NORMAL
INIT_CYCLES = 3


# ─────────────────────────────────────────────
#  FSM Class
# ─────────────────────────────────────────────

class ChipDocFSM:
    def __init__(self, verbose=True):
        self.state = "INIT"
        self.verbose = verbose
        self.tick_count = 0
        self.init_counter = 0
        self.warn_counter = 0   # counts ticks in WARN before escalating to FAULT

        # Latched fault register — set on fault detection, cleared on recovery
        self.fault_latch = {k: False for k in FAULT_KEYS}

        # Live fault flags from comparators this tick
        self.fault_flags = {k: False for k in FAULT_KEYS}

        # Outputs
        self.en_out = False   # held low until NORMAL
        self.health = False   # held low until NORMAL
        self.warn = False     # asserted in WARN state only

        # Log of all state transitions for inspection
        self.log = []

    # ── Internal helpers ──────────────────────

    def _any_fault_active(self):
        return any(self.fault_flags[k] for k in FAULT_KEYS)

    def _any_immediate_fault_active(self):
        return any(self.fault_flags[k] for k in IMMEDIATE_FAULTS)

    def _any_warn_fault_active(self):
        return any(self.fault_flags[k] for k in FAULT_KEYS if k not in IMMEDIATE_FAULTS)

    def _any_latch_set(self):
        return any(self.fault_latch[k] for k in LATCHING_FAULTS)

    def _any_auto_fault_active(self):
        return any(self.fault_flags[k] for k in AUTO_RECOVER_FAULTS)

    def _update_fault_latch(self):
        for k in FAULT_KEYS:
            if self.fault_flags[k]:
                self.fault_latch[k] = True

    def _clear_auto_recover_latches(self):
        for k in AUTO_RECOVER_FAULTS:
            if not self.fault_flags[k]:
                self.fault_latch[k] = False

    def _clear_all_latches(self):
        for k in FAULT_KEYS:
            self.fault_latch[k] = False

    def _set_outputs(self):
        if self.state == "NORMAL" or self.state == "RECOVERY":
            self.en_out = True
            self.health = True
            self.warn = False
        elif self.state == "WARN":
            self.en_out = True   # still enabled
            self.health = True   # still healthy
            self.warn = True     # but warn asserted
        else:
            # FAULT or INIT
            self.en_out = False
            self.health = False
            self.warn = False

    def _record(self, event=""):
        entry = {
            "tick": self.tick_count,
            "state": self.state,
            "en_out": self.en_out,
            "health": self.health,
            "faults": {k: v for k, v in self.fault_flags.items() if v},
            "latches": {k: v for k, v in self.fault_latch.items() if v},
            "event": event,
        }
        self.log.append(entry)
        if self.verbose:
            active_faults = [k for k, v in self.fault_flags.items() if v]
            active_latches = [k for k, v in self.fault_latch.items() if v]
            print(
                f"  tick {self.tick_count:>3} | {self.state:<10} | "
                f"EN_OUT={int(self.en_out)} HEALTH={int(self.health)} WARN={int(self.warn)} | "
                f"faults={str(active_faults or '-'):<30} "
                f"latches={str(active_latches or '-')}"
                + (f" | {event}" if event else "")
            )

    # ── Main tick ─────────────────────────────

    def tick(self, inputs: dict, mr: bool = False):
        """
        Advance the FSM by one cycle.

        inputs: dict with keys from FAULT_KEYS, values True/False
                Missing keys default to False (no fault)
        mr:     manual reset signal (active high in simulator)
        """
        self.tick_count += 1

        # Update live fault flags from comparator inputs
        for k in FAULT_KEYS:
            self.fault_flags[k] = bool(inputs.get(k, False))

        # Update fault latch — once set, latching faults stay until MR
        self._update_fault_latch()

        prev_state = self.state
        event = ""

        # ── State machine ──────────────────────

        if self.state == "INIT":
            self.init_counter += 1
            if self.init_counter >= INIT_CYCLES:
                if self._any_immediate_fault_active():
                    self.state = "FAULT"
                    event = "immediate fault detected during INIT"
                elif self._any_fault_active():
                    self.state = "WARN"
                    self.warn_counter = 1
                    event = "warn-level fault detected during INIT"
                else:
                    self.state = "NORMAL"
                    event = "INIT complete"

        elif self.state == "NORMAL":
            if self._any_immediate_fault_active():
                # OV, HB — skip WARN, go straight to FAULT
                self.state = "FAULT"
                event = f"immediate fault: {[k for k,v in self.fault_flags.items() if v and k in IMMEDIATE_FAULTS]}"
            elif self._any_warn_fault_active():
                # OC, UV, OT — enter WARN first
                self.state = "WARN"
                self.warn_counter = 1
                event = f"warn: {[k for k,v in self.fault_flags.items() if v and k not in IMMEDIATE_FAULTS]}"

        elif self.state == "WARN":
            if self._any_immediate_fault_active():
                # Immediate fault arrives during WARN — escalate now
                self.state = "FAULT"
                self.warn_counter = 0
                event = "immediate fault during WARN — escalating"
            elif self._any_warn_fault_active():
                # Warn-level fault still active — increment counter
                self.warn_counter += 1
                if self.warn_counter >= WARN_TO_FAULT_CYCLES:
                    self.state = "FAULT"
                    self.warn_counter = 0
                    event = f"sustained fault — escalating to FAULT after {WARN_TO_FAULT_CYCLES} cycles"
            else:
                # All faults cleared during WARN — return to NORMAL
                self.warn_counter = 0
                self.state = "NORMAL"
                event = "fault cleared during WARN — returning to NORMAL"

        elif self.state == "FAULT":
            # Auto-recover faults clear their latch when condition clears
            self._clear_auto_recover_latches()

            if not self._any_fault_active() and not self._any_latch_set():
                # All faults cleared, no latching faults held — auto recover
                self.state = "RECOVERY"
                event = "auto-recovery — all faults cleared"
            elif mr and not self._any_fault_active():
                # Latching fault held — requires MR to attempt recovery
                self.state = "RECOVERY"
                event = "MR asserted, faults cleared — attempting recovery"

        elif self.state == "RECOVERY":
            # If faults return during recovery, drop back to FAULT
            if self._any_immediate_fault_active():
                self.state = "FAULT"
                event = "immediate fault during RECOVERY"
            elif self._any_warn_fault_active():
                self.state = "WARN"
                self.warn_counter = 1
                event = "warn-level fault during RECOVERY — entering WARN"
            else:
                # Clear all latches and return to NORMAL
                self._clear_all_latches()
                self.state = "NORMAL"
                event = "recovery complete"

        # Update outputs based on new state
        self._set_outputs()

        if self.state != prev_state and not event:
            event = f"{prev_state} → {self.state}"

        self._record(event)

    def reset(self):
        """Hard reset — simulates power cycle."""
        self.__init__(verbose=self.verbose)

    def print_summary(self):
        print("\n── Fault latch summary ──")
        for k, v in self.fault_latch.items():
            print(f"  {k:<8}: {'LATCHED' if v else 'clear'}")
        print(f"  State  : {self.state}")
        print(f"  EN_OUT : {int(self.en_out)}")
        print(f"  HEALTH : {int(self.health)}")


# ─────────────────────────────────────────────
#  Scenario Runner
# ─────────────────────────────────────────────

def run_scenario(name, steps, verbose=True):
    """
    Run a named fault injection scenario.

    steps: list of (inputs_dict, mr, description) tuples
    """
    print(f"\n{'═'*70}")
    print(f"  SCENARIO: {name}")
    print(f"{'═'*70}")
    print(f"  {'tick':>4}   {'state':<10}   outputs          faults / event")
    print(f"  {'─'*64}")

    fsm = ChipDocFSM(verbose=verbose)

    for inputs, mr, desc in steps:
        if desc:
            print(f"\n  ── {desc}")
        fsm.tick(inputs, mr=mr)

    fsm.print_summary()
    return fsm


# ─────────────────────────────────────────────
#  Scenarios
# ─────────────────────────────────────────────

def scenario_normal_powerup():
    """Clean power-up, no faults. Should reach NORMAL after INIT."""
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "steady state"),
        ({}, False, ""),
    ]
    return run_scenario("Normal power-up", steps)


def scenario_overcurrent_auto_recover():
    """
    OC on rail A asserted for a few ticks then clears.
    OC is an auto-recover fault — should return to NORMAL
    once fault clears and MR is asserted.
    """
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "NORMAL"),
        ({"oc_a": True}, False, "overcurrent rail A detected"),
        ({"oc_a": True}, False, ""),
        ({"oc_a": False}, False, "OC clears — fault gone but latched in FAULT state"),
        ({}, True,  "MR asserted — attempt recovery"),
        ({}, False, "MR released — should be NORMAL"),
    ]
    return run_scenario("Overcurrent rail A — auto recover", steps)


def scenario_overvoltage_latch():
    """
    OV on rail B — a latching fault.
    Should stay in FAULT even after fault clears until MR.
    """
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "NORMAL"),
        ({"ov_b": True}, False, "overvoltage rail B — latching fault"),
        ({"ov_b": True}, False, ""),
        ({"ov_b": False}, False, "OV clears — but should stay in FAULT (latching)"),
        ({}, False, "still in FAULT without MR"),
        ({}, True,  "MR asserted — attempt recovery"),
        ({}, False, "should be NORMAL"),
    ]
    return run_scenario("Overvoltage rail B — latching", steps)


def scenario_missing_heartbeat():
    """
    Heartbeat missing — a latching fault.
    Simulates upstream MCU dying.
    """
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "NORMAL — heartbeat healthy"),
        ({}, False, ""),
        ({"hb": True}, False, "watchdog timeout — heartbeat missing"),
        ({"hb": True}, False, ""),
        ({"hb": False}, False, "hb signal restored but still latched"),
        ({}, True,  "MR asserted"),
        ({}, False, "NORMAL restored"),
    ]
    return run_scenario("Missing heartbeat — latching", steps)


def scenario_fault_during_init():
    """
    Fault present during INIT — should go directly to FAULT
    without ever reaching NORMAL.
    """
    steps = [
        ({"uv_a": True}, False, "power up with undervoltage on rail A"),
        ({"uv_a": True}, False, ""),
        ({"uv_a": True}, False, "INIT completes — should go to FAULT not NORMAL"),
        ({"uv_a": False}, True,  "UV clears, MR asserted"),
        ({}, False, "should recover to NORMAL"),
    ]
    return run_scenario("Fault present during INIT", steps)


def scenario_multiple_faults():
    """
    Multiple faults asserted simultaneously.
    All must clear and MR asserted before recovery.
    """
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "NORMAL"),
        ({"oc_a": True, "uv_b": True, "ot": True}, False, "three faults simultaneously"),
        ({"oc_a": False, "uv_b": True, "ot": True}, False, "OC clears"),
        ({"oc_a": False, "uv_b": False, "ot": True}, False, "UV clears"),
        ({"oc_a": False, "uv_b": False, "ot": False}, False, "OT clears — all gone"),
        ({}, True,  "MR asserted"),
        ({}, False, "NORMAL"),
    ]
    return run_scenario("Multiple simultaneous faults", steps)


def scenario_fault_during_recovery():
    """
    New fault appears during RECOVERY window.
    Should drop back to FAULT immediately.
    """
    steps = [
        ({}, False, "power up"),
        ({}, False, ""),
        ({}, False, ""),
        ({}, False, "NORMAL"),
        ({"oc_a": True}, False, "overcurrent rail A"),
        ({"oc_a": False}, True,  "OC clears, MR asserted — entering RECOVERY"),
        ({"ov_a": True}, False,  "new fault during RECOVERY — should drop to FAULT"),
        ({"ov_a": False}, True,  "OV clears, MR asserted again"),
        ({}, False, "NORMAL"),
    ]
    return run_scenario("Fault during recovery window", steps)


# ─────────────────────────────────────────────
#  Interactive Mode
# ─────────────────────────────────────────────

INTERACTIVE_FAULTS = {
    "1": ("oc_a", "Overcurrent rail A"),
    "2": ("oc_b", "Overcurrent rail B"),
    "3": ("uv_a", "Undervoltage rail A"),
    "4": ("ov_a", "Overvoltage rail A"),
    "5": ("uv_b", "Undervoltage rail B"),
    "6": ("ov_b", "Overvoltage rail B"),
    "7": ("ot",   "Overtemperature"),
    "8": ("hb",   "Heartbeat missing"),
}

def print_interactive_help():
    print("""
  ── Fault inputs (combine with spaces e.g. '1 3') ──
    1  oc_a   overcurrent rail A      (auto-recover)
    2  oc_b   overcurrent rail B      (auto-recover)
    3  uv_a   undervoltage rail A     (auto-recover)
    4  ov_a   overvoltage rail A      (latching)
    5  uv_b   undervoltage rail B     (auto-recover)
    6  ov_b   overvoltage rail B      (latching)
    7  ot     overtemperature         (auto-recover)
    8  hb     heartbeat missing       (latching)

  ── Control ──
    m  or mr   assert manual reset this tick
    n  or ok   no faults, normal tick
    r          reset (power cycle)
    q          quit
    ?          show this help
    """)

def print_tick_interactive(fsm):
    active  = [k for k, v in fsm.fault_flags.items() if v]
    latched = [k for k, v in fsm.fault_latch.items() if v]
    fault_str  = str(active)  if active  else "-"
    latch_str  = str(latched) if latched else "-"
    warn_str   = f"  warn_count={fsm.warn_counter}" if fsm.state == "WARN" else ""
    print(
        f"  tick {fsm.tick_count:>3} | {fsm.state:<10} | "
        f"EN_OUT={int(fsm.en_out)}  HEALTH={int(fsm.health)}  WARN={int(fsm.warn)}  "
        f"faults={fault_str}"
        + (f"  latched={latch_str}" if latched else "")
        + warn_str
    )

def interactive_mode():
    print(f"\n{'═'*70}")
    print("  CD1624 INTERACTIVE MODE")
    print("  Each input = one clock tick. Type fault numbers to inject.")
    print(f"{'═'*70}")
    print_interactive_help()

    fsm = ChipDocFSM(verbose=False)

    print("  Powering up...")
    while fsm.state == "INIT":
        fsm.tick({})
    print(f"  INIT complete — now in NORMAL\n")
    print(f"  {'tick':>4}   {'state':<10}   EN_OUT   HEALTH   faults")
    print(f"  {'─'*56}")
    print_tick_interactive(fsm)

    while True:
        try:
            raw = input("\n  > ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            print("\n  Exiting.")
            break

        if not raw:
            continue
        if raw in ("q", "quit", "exit"):
            print("  Exiting.")
            break
        if raw in ("?", "help"):
            print_interactive_help()
            continue
        if raw in ("r", "reset"):
            fsm = ChipDocFSM(verbose=False)
            while fsm.state == "INIT":
                fsm.tick({})
            print("  Power cycled — back in NORMAL\n")
            print(f"  {'tick':>4}   {'state':<10}   EN_OUT   HEALTH   faults")
            print(f"  {'─'*56}")
            print_tick_interactive(fsm)
            continue

        tokens = raw.split()
        inputs = {}
        mr = False
        valid = True

        for token in tokens:
            if token in ("m", "mr"):
                mr = True
            elif token in ("n", "ok"):
                pass
            elif token in INTERACTIVE_FAULTS:
                key, _ = INTERACTIVE_FAULTS[token]
                inputs[key] = True
            else:
                print(f"  Unknown input '{token}' — type ? for help")
                valid = False
                break

        if not valid:
            continue

        fsm.tick(inputs, mr=mr)
        print_tick_interactive(fsm)


# ─────────────────────────────────────────────
#  Entry point
# ─────────────────────────────────────────────

if __name__ == "__main__":
    import sys

    print("CD1624 Behavioral FSM Simulator")
    print("ChipDoc — Jonathan Song, Summer 2026")
    print()
    print("  python3 fsm_sim.py      run all scenarios")
    print("  python3 fsm_sim.py -i   interactive mode")
    print("  python3 fsm_sim.py -s   scenarios then interactive")
    print()

    mode = sys.argv[1] if len(sys.argv) > 1 else ""

    if mode == "-i":
        interactive_mode()

    elif mode == "-s":
        scenario_normal_powerup()
        scenario_overcurrent_auto_recover()
        scenario_overvoltage_latch()
        scenario_missing_heartbeat()
        scenario_fault_during_init()
        scenario_multiple_faults()
        scenario_fault_during_recovery()
        print(f"\n{'═'*70}")
        print("  All scenarios complete.")
        print(f"{'═'*70}\n")
        interactive_mode()

    else:
        scenario_normal_powerup()
        scenario_overcurrent_auto_recover()
        scenario_overvoltage_latch()
        scenario_missing_heartbeat()
        scenario_fault_during_init()
        scenario_multiple_faults()
        scenario_fault_during_recovery()
        print(f"\n{'═'*70}")
        print("  All scenarios complete.")
        print(f"{'═'*70}\n")