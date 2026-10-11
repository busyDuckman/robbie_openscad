include <BOSL2/std.scad>
include <BOSL2/gears.scad>
include <NopSCADlib/vitamins/stepper_motors.scad>
include <NopSCADlib/vitamins/extrusions.scad>
include <screw_holes.scad>
include <components.scad>

/*
Vocab:
  base: tube on which robbie sits
  collar: the colar with an internal ring gear and channel for the sleds
*/

LOD = 1.0; //0.25;

base_od = 150;
base_id = 100;
base_cable_dia = 12;
base_h = 40;

collar_h = 10;
collar_gear_h = 8;

// gears
gear_mod=1.5;
ring_gear_teeth = 56;
pinion_teeth = 9;
// < 17 teeth needs profile shift to avoid undercut; ring must use the same shift
pinion_shift = auto_profile_shift(teeth=pinion_teeth);
pinion_shaft_fit = 0.0; // added to the n20 D hole, 0 = nominal (press fit on X1C 0.2 nozzle), + looser, - tighter


//parts
magnet_d = 5.98; //ie should fit a 6mm hole
magnet_h = 2.5; //ie should fit a 6mm hole
magnet_offset = 1.0; // adjust to soud magnet strength


// printer tolerances
backlash=0.1;

// self tapping screws
my_screw = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_METAL;
my_screw_no_head = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_FOR_METAL;
my_screw_gauge=6;
    
function half_way(a, b) = (a + b) / 2;

function collar_od() = half_way(base_od, base_id);
function collar_holes_r() = 110/2; //half_way(collar_od(), base_id) / 2;

module base() {
    chamf = (collar_od() - base_id)/2;
    
    color("gray")
    
    render()
    difference() {
        tube(id=base_id, od=base_od, h=base_h , ochamfer2=chamf, anchor=BOTTOM, $fn=512*LOD);
        
        xcyl(h=base_od/1.9, d=base_cable_dia, $fn=64*LOD, anchor=RIGHT);
        
        up(base_h)
        zrot_copies(n=8, r=collar_holes_r())
        self_tap_hole(gauge=my_screw_gauge, length=25, screw_type=my_screw_no_head,
                  hole_type=HOLE_TRI_TWIST, anchor=TOP, sink=0.5);
    }
    
    


}

module collar() {
    color("blue")
    render()
    difference() {
        union() {
            tube(id=base_id, od=collar_od(), h=collar_h, anchor=BOTTOM, $fn=512);
            
            //outer collar
            tube(id=collar_od()-6, od=collar_od(), h=collar_h+3, anchor=BOTTOM, $fn=512);
            
            // inner collar
            tube(id=collar_od()-32, od=base_id, h=collar_h+3, chamfer=0.5, anchor=BOTTOM, $fn=512);
            
            ring_gear(mod=gear_mod, teeth=ring_gear_teeth , thickness=collar_gear_h, backing=10, profile_shift=pinion_shift,
                backlash=backlash, anchor=BOTTOM, $fn=512*LOD);
        }
    
        up(collar_h)
        zrot_copies(n=8, r=collar_holes_r())
            self_tap_hole(gauge=my_screw_gauge, length=25, screw_type=my_screw,
                  hole_type=HOLE_CLEARANCE, anchor=TOP, sink=5);
          //cyl(h=20, d=6, $fn=64*LOD, anchor=BOTTOM);
    }
          
}

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
    zrot(angle) fwd(pinion_dist()) children();
}

module pinion(gear_spin=0) {
    collar_od = magnet_d+4;
    
    color("orange")
    union() {
        up(collar_gear_h)
        //cyl(d=collar_od, h=magnet_offset, anchor=BOTTOM, $fn=128*LOD);
        tube(id=magnet_d-2, od=collar_od, h=magnet_offset, ochamfer1=-0.5, 
             anchor=BOTTOM, $fn=128*LOD);
        
    
        up(collar_gear_h+magnet_offset)
        tube(id=magnet_d, od=collar_od, h=magnet_h, ochamfer2=0.25, 
             anchor=BOTTOM, $fn=128*LOD);
    
        difference() {
            spur_gear(mod=gear_mod, teeth=pinion_teeth, thickness=collar_gear_h,
                    profile_shift=pinion_shift, backlash=backlash,
                    gear_spin=gear_spin, anchor=BOTTOM, $fn=128*LOD);

            zrot(gear_spin)
            pinion_shaft_hole(collar_gear_h);
        }
    }
}

// D hole for the n20 shaft, from z=0 up, with a small lead-in chamfer at the bottom
module pinion_shaft_hole(h) {
    d = n20_shaft.x + pinion_shaft_fit;
    flat = n20_shaft.y + pinion_shaft_fit;

    down(0.01)
    intersection() {
        cyl(d=d, h=h + 0.02, anchor=BOTTOM, $fn=64);
        fwd((d - flat)/2)
        cuboid([d, flat, h + 0.02], anchor=BOTTOM);
    }

    down(0.01)
    cyl(d1=d + 0.6, d2=d, h=0.3, anchor=BOTTOM, $fn=64);
}

// pinion meshed with the collar's ring gear at `angle`
module pinion_at(angle) {
    at_pinion(angle) {
        pinion(gear_spin=pinion_spin(angle));
    }
}

// The basic sled shape, used as a building block for multiple parts
//   - A circle around the pinion shaft that extends to join on a segment 
//     of a greater circle (greater_d).
//   - slice_d is the dia of a common ciricle to whicht the slice angle (slice_a) opertates.
//     In this way the shape edges match, regadrless of the greader circle size.
module sled_shape(h, pinion_hole_d, slice_a = 45, slice_d = base_id, greater_d) {
    greater_d = is_def(greater_d) ? greater_d : slice_d;
    r = 33/2;
    c = [0, pinion_dist()]; // origin, in the sled frame

    // far points along each side, s = -1 left, 1 right
    far = [for (s = [-1, 1]) let(
                p = c + slice_d/2 * [sin(s*slice_a/2), -cos(s*slice_a/2)],
                l = norm(p),
                phi = atan2(p.y, p.x),
                t = r * [cos(phi + s*acos(r/l)), sin(phi + s*acos(r/l))] // tangent point
           ) t + (p - t) * 10];
    assert(far[1].x > far[0].x, "sled_shape: slice_a too small, sides must flare out from the shaft circle");

    linear_extrude(h)
    difference() {
        intersection() {
            hull() {
                circle(r=r, $fn=128*LOD);
                polygon([far[0], far[1], [0, 0]]);
            }
            translate(c) circle(d=greater_d, $fn=512*LOD);
        }
        if (is_def(pinion_hole_d))
            circle(d=pinion_hole_d, $fn=64*LOD);
    }
}

//stack some sled_shape() of differen outer circles sise on top of each other to check alignments.
module sled_demo() {
    sizes = [base_id - 10, base_id, base_id + 10, base_id + 20];
    for (i = idx(sizes))
        up(i * 2)
        color(["red", "green", "blue", "orange"][i])
        sled_shape(2, pinion_hole_d=n20_shaft.x, greater_d=sizes[len(sizes) - 1 - i]);
}


module sled_assembly(pionion_r=0) {
    down(3)
        n20_motor();
    pinion(gear_spin=pionion_r);
    
    down(3)
    sled_shape(3);
    
    /*
    up(10)
    sled_shape(6, greater_d=collar_od()-6, pinion_hole_d=10);
    
    up(20)
    yrot(180)
    //zrot(45)
    as5600_board(headers=BOTTOM);
    */
}


part = 0;

// full assembly
if(part == 0) {
    # base();
    up(base_h)
    collar();
    
    

    up(base_h)
    for(angle = [0, 120, 240]) {
        at_pinion(angle)
            sled_assembly(pionion_r=pinion_spin(angle));
        // pinion_at(angle);
    }
}

if(part == 1) {
    base();
}

if(part == 2) {
    collar();
}

if(part == 4) {
    sled_assembly();
}







