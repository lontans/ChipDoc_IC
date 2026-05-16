```
CD1624
└── CD   : ChipDoc
└── 16   : 16-pin package
└── 2    : dual-mode (analog / digital)
└── 4    : four monitored variables (voltage, current, temperature, heartbeat)
```

## Reading through existing IC datasheets for inspiration

### Studying the TPS3700:
- Adjustable voltage threshold (down to 400mV)
- 5.5uA quiescent current
- Wide voltage input range

Voltage Ratings:
- VDD -0.3 -> 20V
- Output -0.3 -> 20V, assume this is same as VDD
- INA+, INB- -0.3 ->7V max. VDD,Output, INA+/- based on same network ground

Internal 400mV reference, two open drain outputs
- Can be used as window voltage detector or as two independent voltage monitors. External resistors set monitored voltage
- OUTA pin low when positive voltage drops below V(ITP)-V(HYS). Hysterisis filters rejects brief glitches, avoids false triggering
- Internal hysteresis: 5.5mV (guessing this is resilience against noise)
- V(ITP) stands for initial threshold point
- Hysteresis: fixed for analog mode, possibly I2C trimmable. The important part is that after a fault is triggered, to turn the healthy signal on again you need to go further over or further under the "safe" line

Latching:
- Both OUTA and OUTB return to HIGH (healthy) state when sense voltage returns above the threshold, no external "ok" signal needed

Delay:
- High-Low Prop delay = 18 microseconds
- Low-High Prop delay = 29 microseconds
- Theres also OUT rise/fall time, around 2.2 microseconds
- Fault Persistence Thresholds: TBD, ~10us before WARN pulsed

How the comparison works:
- Two comparators. Comparator internally connected to a reference. Reference voltage  should be equal to the comparator rising threshold, so in a good state corresponding output is driven high. Inveter NOT gate means a LOW signal is sent to N fet which keeps OUT high, logic high means healthy
- Other voltage detector method is window, basically just glancing/sampling in parallel, resistor divider network used for this. In window mode OUTB is HIGH when not overvoltage and OUTA is HIGH whem not undervoltage so AND of those is safe threshold
- OUTA and OUTB share voltage with INA+ and INB-
- For ChipDoc: minimum 4 (UV+OV × 2 rails)

States:
- Normal: Vdd > UVLO, so above 1.8V
- Undervoltage Lockout: V (power on reset) < Vdd < UVLO: OUTA and OUTB signals are asserted, high impedance regardless of INA+ and INB-
- Power-On Reset (Vdd < V(power off reset)): Voltage Vdd is lower than POR, unable to internally pull asserted output to ground, both outputs in high impedance state

Application Notes:
- Outputs often tied to VDD through pullup resistor, but sometimes outputs pulled to higher or lower voltage than Vdd to interface with external peripherals
- Many types of configurations based on desired sensing type
- IC can't do under and overvoltage for a rail just with one pin. Chipdoc should optimize for one use case (2 rail over+under sensing) with the option to float one rail. Disadvantage would be two pints would alow for resistor divider setting threshold for both under and overvoltage, seems this IC is limited to one for each
- Remember good analog practice, 0.1uF Vdd cap, potentially 1nF-10nF cap near INA+ and INB- terminals, reduces sensitivity to transients

For ChipDoc:
- It should immediately output a WARN signal when the threshold is passed, and if the over/undervoltage is over or under by enough it should kill the full HEALTH signal
- Needs to sense over and undervoltage on two rails with 2 pins if possible. Maybe have more comparators, inverter to achieve this in architecture?

### Studying the MAX6316:
- Supervisory circuit, 5 pin, watchdog, manual reset

System Level Behavior:
- Low operating voltage range (1V-5v5)
- Low quietescent current (10-20uA)
- Reset Thershold Temperature: Delta Threshold/Degree Celsius = 40. Generally 1.5% above and below average temp
- Reset Output Voltage: 0.3V
- Note: Factory-trimmed voltage divider programs nominal temp reset threshold, factory trimmed reset threshold can be adjusted
- Watchdog input threshold, input current, pulse width units are in the datasheet. Multiple modules have different timeout periods (e.g 4.3-9.3ms, 71-153ms, 18-38 seconds). Watchdog pulse width always 50ns. Input threhold should be between 0.3-0.7 of Vcc

MAX6316 Functions:
- 1: Active Low, Reset Output
- 3: MR, Active Low Reset Input, pull low to force reset
- 4: WDI, watchdog input, triggers reset if remains either too high or low for duration of watchdog timeout period. Pin can be No-Connect

Reset Input/Output:
- Input starts or resets uP in a known state. Reset output interfaces with reset input to prevent code-execution errors. Reset can also be asserted despite the MAX6316 being stuck in infinite loop.
- Reset output is active low. Reset is asserted when Vcc is below reset threshold, MR (manual reset) is pulled low, or if WDI pins (watchdog input) is not serviced within the watchdog timeout period
- Reset remains asserted for specified reset active timeout period after any above condition is met, reset active timeout period (tRP) determines when reset output deasserts so resest only changes for one timeout period

Extra Notes:
- Bidirectional Reset Pins exist for certain versions of the MAX6316 for systems where serveral devices connect to reset.
- Much more complex block diagram, contains active pullup enable comparators, transition flip-flops, "watchdog circuitry" + reset generator black box. reset generator gets inputs from Vcc, Watchdog circuitry and manual reset, outputting signal to N fet that shorts reset to ground
- Timer is cleared internally at intervals equal to 7/8 of watchdog period when WDI is NC
- Datasheet references uP (Microprocessor) a lot since it is meant as a microprocessor supervisor, pretty standard connections
- WDI basically means uP needs to pulse within the period otherwise reset is asserted. Watchdog timeout period cannot be manually changed, just based on package purchased. Pulse width is standard 50ns
- ChipDoc should either be standardized for watchdog period or have internal circuitry that selects different module immediates based on freq, tbd

## Synthesized ChipDoc Initial Decisions Based on the Datasheets:
Overcurrent:       WARN → FAULT if persists > Xµs. Auto-recover when cleared.
Undervoltage:      WARN → FAULT if persists > Xµs. Auto-recover with delay.
Overvoltage:       FAULT immediately. Latch until I2C clear or power cycle.
Missing heartbeat: FAULT after timeout. Latch.
Overtemperature:   WARN only (v1). No auto-kill.

## ChipDoc Pinout Idea
| Pin # | Name | Function | Direction | Notes |
|---|---|---|---|---|
| 1 | INA+ | Current sense rail 1, positive | Input | Differential shunt sense |
| 2 | INA− | Current sense rail 1, negative | Input | Differential shunt sense |
| 3 | INB+ | Current sense rail 2, positive | Input | Differential shunt sense |
| 4 | INB− | Current sense rail 2, negative | Input | Differential shunt sense |
| 5 | VSENA | Voltage sense rail 1 | Input | Resistor divider to internal ref |
| 6 | VSENB | Voltage sense rail 2 | Input | Resistor divider to internal ref |
| 7 | TEMP | Temperature sense | Input | External NTC thermistor |
| 8 | GND | Ground | Power | — |
| 9 | VCC | Supply voltage | Power | 0.1µF decoupling cap to GND |
| 10 | ADDR | I2C address select | Input | Sampled at power-on only |
| 11 | SCL | I2C clock | Input | Digital mode only |
| 12 | SDA | I2C data | Bidirectional | Digital mode only |
| 13 | MR | Manual reset | Input | Active-low, releases FAULT latch |
| 14 | HB | Heartbeat / watchdog input | Input | Must pulse within timeout or FAULT |
| 15 | HEALTH | System health indicator | Output | Open-drain, deasserts on FAULT |
| 16 | EN_OUT | Enable output / kill signal | Output | Open-drain, latches low on FAULT |
