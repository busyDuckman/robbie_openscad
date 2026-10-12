# Rotary platform brief

Source of truth: `base.scad`, `components.scad`. Numbers below are current defaults.

## Layout
- Fixed internal **ring gear**, 56 teeth, module 1.5, in the collar on top of the base tube (bore Ø100).
- **3 sleds** ride the ring, each a planet with its own **9 tooth pinion** on its own **GA12-N20 motor** (D shaft, direct drive). Pinion centre is 35.25 mm from the ring centre.
- Sleds are **independent** but share one track: they **cannot pass each other**. Order is fixed and the controller must keep them from colliding. Assembly default spacing is 120°.

## Kinematics (per sled)
- Sled orbit angle = pinion angle (relative to the sled) × 9/56. One orbit = 56/9 ≈ 6.22 pinion turns.
- Motor gearbox ratio depends on the N20 variant fitted, so measure it.
- Angle convention: sled at 0° sits at −Y, positive is CCW about +Z.

## Encoders
- One **AS5600** per sled, over a magnet on top of its pinion. It reads the pinion angle relative to the sled: 12 bit, ≈ 25,500 counts per sled orbit.
- It is absolute only within one pinion turn, so the sled's orbit position needs turn counting plus a home.
- I²C address is fixed (0x36), so 3 sleds need a mux (e.g. TCA9548A), separate buses, or analogue/PWM out.
- Wiring is 4 wires per sled (VCC, GND, SDA, SCL), dropped down through the sled. Cable management for orbiting sleds isn't designed yet.

## Home switch
- **One** lever-less D2F micro switch in the base wall, at base angle 180° (−X, above the cable hole), with its button facing into the bore. That is sled angle 270° in the convention above.
- Each sled has a **fob**, a Ø6 post under its lower sled on the sled centreline, flush with the bore (r = 50).
- Every sled presses the same switch, so the switch doesn't say which sled. Home one sled at a time, or infer which sled from the encoder positions.
- The fob is pressed from **either direction**: its corners have rounded lead-ins on both sides. The switch is closed over a short arc, about 5–7° of orbit (fob width minus the button's travel).
- The leading edge differs with direction (hysteresis), so take home as the **midpoint of the press window**, or always approach from the same side. Calibrate the window on hardware.
