# ChipDoc_IC
Mixed-Signal Watchdog IC

ChipDoc is a 16-pin Watchdog IC which monitors voltage rails, current draw, temperature, and heartbeat activity in circuits. It has an analog and digital mode, meaning it can either be operated with or without an external microcontroller. In analog mode safety thresholds are preset/only rudimentally configurable, whereas in digital mode ChipDoc accepts an I2C signal encoding safety threholds and writebacks current levels on the same line. For both modes, ChipDoc outputs a HEALTH, WARNING, and FAULT signal to indicate current state. 

Current Status: Architecture, Orientation, State Definition

## What it Monitors + Outputs:

| Info          | I/O | Purpose |
| ------------- | ------------- | --------- |
| MODE          | Input  | Choose Analog/Digital Mode |
| Current A/B   | Input  | Monitors Overcurrent, Undercurrent, Transients on 2 rails |
| Voltage A/B   | Input  | Monitors Overvoltage, Undervoltage on 2 rails |
| Temperature   | (Optional) Input  | Senses the current on thermistor rail indicating temperature changes  |
| Heartbeat     | (Optional) Input  | Listens for a constant-frequency HB signal |
| HEALTH        | Output  | Listens for a constant-frequency HB signal |
| FAULT         | Output  | Listens for a constant-frequency HB signal |
| WARN          | Output  | Listens for a constant-frequency HB signal |

## Repo Structure:
```
chipdoc/
├── README.md
├── docs/
│   ├── architecture.md     ← block diagrams, design decisions
│   ├── register_map.md     ← I2C registers (fill in Phase 3)
├── sim/
│   └── fsm_sim.py          ← Python behavioral simulator
├── rtl/
│   └── (Verilog modules)
├── tb/
│   └── (testbenches)
└── notebook/
    └── log.md              ← running progress log
    └── TODO.md             ← todolist!
```
## Design Principles:
- Autonomous Safety Path
- 16-pin standard package
- Drop-in configurability
- Reliability + Worst-Case self-safety protection

## How to run the sim:
- tbd


