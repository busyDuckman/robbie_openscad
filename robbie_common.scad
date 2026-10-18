include <BOSL2/std.scad>
include <BOSL2/gears.scad>
include <BOSL2/rounding.scad>
include <BOSL2/screws.scad>
include <NopSCADlib/vitamins/stepper_motors.scad>
include <NopSCADlib/vitamins/extrusions.scad>
include <screw_holes.scad>
include <components.scad>
include <helpers.scad>
use <nop_screws.scad>

/*
Shared by base.scad and sled.scad: library includes, the base / collar / gear sizes the sleds
are built around, and the ring gear placement functions. Use include <robbie_common.scad>.
*/

// ----------------------------------------------------------------------------------------
// Globals
// ----------------------------------------------------------------------------------------

LOD = 0.5; // 0.25 for speed, 1.0 for checks, 2.0 for prints;

base_od = 150;
base_id = 100;
base_cable_dia = 12;
base_h = 40;
base_chamfer_h = 15;    // vertical drop of the outer top chamfer (horizontal is set by the collar od)

guide_id = 20;
guide_h = 10;

collar_h = 10;
collar_gear_h = 8;

// gears
gear_mod=1.5;
ring_gear_teeth = 56;
pinion_teeth = 9;
// < 17 teeth needs profile shift to avoid undercut; ring must use the same shift
pinion_shift = auto_profile_shift(teeth=pinion_teeth);

// printer tolerances
backlash=0.1;

// self tapping screws
my_screw = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_METAL;
my_screw_no_head = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_FOR_METAL;
my_screw_gauge=6;
    
function half_way(a, b) = (a + b) / 2;

function collar_od() = half_way(base_od, base_id);

// ----------------------------------------------------------------------------------------
// Shared geometry
// ----------------------------------------------------------------------------------------

module inner_collar_ring(e=0, notches=false)
{
    render(convexity=10)
    tube(id=collar_od()-32-e*2, od=base_id+e*2, h=collar_h+3+e, 
         chamfer2=0.5, anchor=BOTTOM, $fn=512*LOD);
}

// ring gear tooth tips, from the collar centre (internal teeth: addendum reduced by the shift)
function ring_tip_r() = pitch_radius(mod=gear_mod, teeth=ring_gear_teeth) - gear_mod * (1 - pinion_shift);

// distance from the origin to pinion centre
function pinion_dist() = gear_dist(mod=gear_mod, teeth1=pinion_teeth, teeth2=ring_gear_teeth,
                                   profile_shift1=pinion_shift, profile_shift2=pinion_shift, internal2=true);

// pinion centre when it has travelled `angle` degrees around the ring (0 = -Y)
function pinion_pos(angle) = zrot(angle, p=[0, -pinion_dist(), 0]);

// pinion's spin relative to the at_pinion() frame so its teeth stay meshed at `angle`
// (half a tooth extra when the tooth counts have different parity)
function pinion_spin(angle) = -angle * ring_gear_teeth / pinion_teeth
                            + ((pinion_teeth + ring_gear_teeth) % 2) * 180 / pinion_teeth;

// move children to the pinion position, turning with the orbit (sled frame, +Y faces collar centre)
module at_pinion(angle) {
    zrot(angle)
        fwd(pinion_dist())
            children();
}