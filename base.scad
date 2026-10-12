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

// ----------------------------------------------------------------------------------------
// Globals
// ----------------------------------------------------------------------------------------

LOD = 0.5; //0.25;

base_od = 150;
base_id = 100;
base_cable_dia = 12;
base_h = 40;
base_chamfer_h = 15;    // vertical drop of the outer top chamfer (horizontal is set by the collar od)

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
magnet_offset = 1.0; // adjust to set magnet strength


// printer tolerances
backlash=0.1;

// self tapping screws
my_screw = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_METAL;
my_screw_no_head = SCREW_UNIT_UK_GAUGE_NARROW + SCREW_FOR_METAL;
my_screw_gauge=6;
    
function half_way(a, b) = (a + b) / 2;

function collar_od() = half_way(base_od, base_id);
function collar_holes_r() = 110/2; //half_way(collar_od(), base_id) / 2;
collar_holes_sa = 360/8/2; // half a step, so no screw sits over the cable hole / home switch

home_switch_a = 180;       // above the cable hole (-X)
home_switch_press = 0.25;  // fob pushes the plunger this far past its click point (d2f overtravel ~0.5)
home_switch_fit = 0.2;     // pocket clearance
home_switch_plug_fit = 0.05; // plug in the pocket
home_switch_plug_corner_r = 0.6; // rounds the plug's back corners, so the pocket's corners aren't the tight spot
home_switch_overcut = 2;   // pocket runs this far past the switch face into the bore, no thin base slivers
home_switch_drop = 1;      // switch top below the lower sled, plug height = lower_sled_h + this
home_switch_wedge = 1.5;   // plug is this much wider each side at the back than at the bore
home_switch_guard_min = 0.4; // thinnest base sliver kept in front of the switch as its forward guard
home_switch_solder_d = 3.2;  // room round each terminal for a wrapped wire and a generous solder blob

upper_sled_z = 10; // upper sled bottom above the collar bottom
lower_sled_h = 3;  // lower sled thickness, hangs below the collar bottom

fob_h = 10;         // post under the lower sled
fob_d = 6;
fob_flare = 1;     // flare where it meets the sled
fob_lead_in = .5;   // rolling_interface() size on the corners, so it rides over the home switch
sled_lead_in = .5;  // same, on the lower sled's outer corners

sensor_gap = 1;    // magnet top to as5600 chip face (datasheet 0.5 - 3)
sensor_fit = 0.2;  // pocket clearance around the pcb
sensor_standoff = 2.5; // stilt height, wire room between the pocket floor and the chip-side face
sensor_peg_fit = 0.1;  // stilt pegs in the pcb holes, on the diameter
pocket_wall = 0.8;     // between the sensor pocket and the collar ring groove

guard_t = 1.0;     // magnet guard wall
guard_gap = 0.5;   // guard top below the chip-side face, clears smd parts
guard_id = 10;     // matches the pinion hole in the upper sled

wire_d = 1.2;      // wire od (28 AWG silicone)
wire_n = 4;        // vcc, gnd, sda, scl
wire_channel = [wire_n*wire_d + 1, wire_d + 1]; // width, depth of the drop channel
wire_channel_shift = 2; // move the channel off the fairing wall towards the pinion, a conduit fills the gap


fairing_t = 1.6;   // wall thickness
fairing_fit = 1.0; // clearance to the ring gear tips


// ----------------------------------------------------------------------------------------
// Geometry
// ----------------------------------------------------------------------------------------

module base() {
    chamf = (collar_od() - base_id)/2;
    
    color("gray")
    
    render()
    difference() {
        // outer top chamfer: chamf in, base_chamfer_h down (tube() has no chamfer angle, so cyl minus bore)
        cyl(d=base_od, h=base_h, chamfer2=chamf, chamfang2=atan(base_chamfer_h / chamf),
            anchor=BOTTOM, $fn=512*LOD);
        cyl(d=base_id, h=3*base_h, $fn=512*LOD);

        xcyl(h=base_od/1.9, d=base_cable_dia, $fn=64*LOD, anchor=RIGHT);
        
        up(base_h)
        zrot_copies(n=8, r=collar_holes_r(), sa=collar_holes_sa)
        self_tap_hole(gauge=my_screw_gauge, length=25, screw_type=my_screw_no_head,
                  hole_type=HOLE_TRI_TWIST, anchor=TOP, sink=0.5);

        home_switch_holder();
    }

}

// switch centre (and plunger) height in the base: switch top home_switch_drop under the lower sled,
// so the plug above it is at least as tall as the lower sled it faces
function home_switch_z() = base_h - lower_sled_h - home_switch_drop - d2f_body.y/2;

// d2f switch frame: in the base wall at home_switch_a, plunger pointing in at the bore, body thickness vertical,
// set back so the fob (flush with the bore) pushes the plunger home_switch_press past its click point,
// slid along so the (off centre) plunger sits on home_switch_a
function home_switch_frame() =
    zrot(home_switch_a)
    * move([base_id/2 + d2f_plunger_op_h - home_switch_press, 0, home_switch_z()])
    * zrot(-90) * xrot(90) // switch +Z -> in towards the centre, switch +Y -> up
    * left(d2f_plunger_x);

module position_home_switch() {
    multmatrix(home_switch_frame())
    children();
}

// plug zone of the pocket, switch top up to y1: wedge shaped in plan, wider at the back than at the bore,
// so the plug can't slide out into the bore. inset shrinks it (plug fit)
// corner_r rounds the two back corners (the plug's, so it clears the printed pocket's not-quite-sharp corners)
module home_switch_wedge(y1, inset=0, corner_r=0) {
    c = home_switch_fit;
    y0 = d2f_body.y/2;
    back_z = -d2f_pin.z + inset;
    front_z = d2f_body.z + c + home_switch_overcut;
    back_w = d2f_body.x + 2*c + 2*home_switch_wedge - 2*inset;

    hull() {
        if (corner_r > 0)
            for (s = [-1, 1])
                translate([s * (back_w/2 - corner_r), y0, back_z + corner_r])
                    ycyl(r=corner_r, h=y1 - y0, anchor=FRONT, $fn=24);
        else
            translate([0, y0, back_z])
                cuboid([back_w, y1 - y0, 0.01], anchor=FRONT+BOTTOM);

        translate([0, y0, front_z])
            cuboid([d2f_body.x + 2*c - 2*inset, y1 - y0, 0.01], anchor=FRONT+TOP);
    }
}

// negative: pocket for the lever-less d2f, open up through the base top, plunger hole out to the bore
module home_switch_holder() {
    c = home_switch_fit;
    up_open = base_h - home_switch_z() + 1; // switch +Y is up

    position_home_switch() {
        // body and terminals
        translate([0, -(d2f_body.y/2 + c), -d2f_pin.z])
        cuboid([d2f_body.x + 2*c, d2f_body.y + 2*c, d2f_pin.z + d2f_body.z + c], anchor=FRONT+BOTTOM);

        // in front of the switch the base is left as the forward guard: the slivers between the flat pocket
        // face and the curved bore. open the middle, where they'd be thinner than home_switch_guard_min
        // (measured from home_switch_a, which is at the plunger; clamped to the pocket's ends)
        let(face = base_id/2 + d2f_plunger_op_h - home_switch_press - d2f_body.z - c, // pocket face from the axis
            r = base_id/2,
            half = sqrt(r*r - pow(min(r, face - home_switch_guard_min), 2)),
            lo = max(-half, -(d2f_body.x/2 + c) - d2f_plunger_x),
            hi = min(half, d2f_body.x/2 + c - d2f_plunger_x))
        translate([d2f_plunger_x + (lo + hi)/2, -(d2f_body.y/2 + c), d2f_body.z])
        cuboid([hi - lo, d2f_body.y + 2*c, c + home_switch_overcut], anchor=FRONT+BOTTOM);

        // plug
        home_switch_wedge(up_open);

        // plunger
        translate([d2f_plunger_x, 0, d2f_body.z])
        cuboid([d2f_plunger.x + 2*c, d2f_plunger.y + 2*c, 5], anchor=BOTTOM);
    }
}

// fills the pocket above the switch flush with the base top (the collar holds it down), wedge shaped so it
// can't slide out into the bore, with fingers down behind the switch between the terminals so it can't slide back
// drawn in the switch frame (+Y up, +Z towards the bore), place with position_home_switch()
module home_switch_plug() {
    c = home_switch_fit;
    f = home_switch_plug_fit;
    top_y = base_h - home_switch_z(); // switch +Y is up

    color("orange")
    difference() {
        union() {
            // cap, switch top to base top
            home_switch_wedge(top_y, inset=f, corner_r=home_switch_plug_corner_r);

            // fingers, pocket floor up to the cap, back of the pocket up to the terminal face,
            // slim enough to leave room for a wire wrapped round each terminal and blobbed with solder
            for (x = [-1, 1] * d2f_pin_pitch/2)
                translate([x, -(d2f_body.y/2 + c) + f, -d2f_pin.z + f])
                cuboid([d2f_pin_pitch - home_switch_solder_d, d2f_body.y + c - f + 0.01, d2f_pin.z - f],
                       anchor=FRONT+BOTTOM);
        }

        // flush with the bore (bore brought into the switch frame)
        multmatrix(matrix_inverse(home_switch_frame()))
        cyl(d=base_id, h=3*base_h, $fn=512*LOD);
    }
}


// ----------------------------------------------------------------------------------------
module inner_collar_ring(e=0, notches=false)
{
    render()
    tube(id=collar_od()-32-e*2, od=base_id+e*2, h=collar_h+3+e, 
         chamfer=0.5, anchor=BOTTOM, $fn=512);
}

module collar() {
    color("blue")
    render()
    difference() {
        union() {
            tube(id=base_id, od=collar_od(), h=collar_h, anchor=BOTTOM, $fn=512*LOD);
            
            //outer collar
            tube(id=collar_od()-6, od=collar_od(), h=collar_h+3, anchor=BOTTOM, $fn=512*LOD);
            
            // inner collar
            inner_collar_ring(notches=true);
                
            
            ring_gear(mod=gear_mod, teeth=ring_gear_teeth , thickness=collar_gear_h, backing=10, profile_shift=pinion_shift,
                backlash=backlash, anchor=BOTTOM, $fn=512*LOD);
        }
    
        up(collar_h)
        zrot_copies(n=8, r=collar_holes_r(), sa=collar_holes_sa)
            self_tap_hole(gauge=my_screw_gauge, length=25, screw_type=my_screw,
                  hole_type=HOLE_CLEARANCE, anchor=TOP, sink=5);
          //cyl(h=20, d=6, $fn=64*LOD, anchor=BOTTOM);
    }
          
}

// ----------------------------------------------------------------------------------------
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
        cyl(d=d, h=h + 0.02, anchor=BOTTOM, $fn=64*LOD);
        fwd((d - flat)/2)
        cuboid([d, flat, h + 0.02], anchor=BOTTOM);
    }

    down(0.01)
    cyl(d1=d + 0.6, d2=d, h=0.3, anchor=BOTTOM, $fn=64*LOD);
}

// pinion meshed with the collar's ring gear at `angle`
module pinion_at(angle) {
    at_pinion(angle) {
        pinion(gear_spin=pinion_spin(angle));
    }
}

// ----------------------------------------------------------------------------------------
// The basic sled shape, used as a building block for multiple parts
//   - A circle around the pinion shaft that extends to join on a segment 
//     of a greater circle (greater_d).
//   - slice_d is the dia of a common ciricle to whicht the slice angle (slice_a) opertates.
//     In this way the shape edges match, regadrless of the greader circle size.
module sled_shape(h, pinion_hole_d, slice_a = 45, slice_d = base_id, greater_d) {
    linear_extrude(h)
    sled_profile(pinion_hole_d, slice_a, slice_d, greater_d);
}

// where a sled side meets the slice_d circle, s = -1 left, 1 right
// (the outer corners of a sled whose greater_d = slice_d)
function sled_slice_point(s, slice_a = 45, slice_d = base_id) =
    [0, pinion_dist()] + slice_d/2 * [sin(s*slice_a/2), -cos(s*slice_a/2)];

// where a sled side leaves the shaft circle (r = 33/2) on its way out to sled_slice_point()
function sled_tangent_point(s, slice_a = 45, slice_d = base_id) =
    let(r = 33/2,
        p = sled_slice_point(s, slice_a, slice_d),
        l = norm(p),
        phi = atan2(p.y, p.x))
    r * [cos(phi + s*acos(r/l)), sin(phi + s*acos(r/l))];

// 2D outline of sled_shape()
module sled_profile(pinion_hole_d, slice_a = 45, slice_d = base_id, greater_d) {
    greater_d = is_def(greater_d) ? greater_d : slice_d;
    r = 33/2;
    c = [0, pinion_dist()]; // origin, in the sled frame

    // far points along each side, s = -1 left, 1 right
    far = [for (s = [-1, 1]) let(
                p = sled_slice_point(s, slice_a, slice_d),
                t = sled_tangent_point(s, slice_a, slice_d)
           ) t + (p - t) * 10];
    assert(far[1].x > far[0].x, "sled_shape: slice_a too small, sides must flare out from the shaft circle");

    difference() {
        intersection() {
            hull() {
                circle(r=r, $fn=128*LOD);
                polygon([far[0], far[1], [0, 0]]);
            }
            translate(c)
                circle(d=greater_d, $fn=512*LOD);
        }
        if (is_def(pinion_hole_d))
            circle(d=pinion_hole_d, $fn=64*LOD);
    }
}

// ----------------------------------------------------------------------------------------
// heights in the sled frame (z=0 at the collar bottom)
function magnet_top() = collar_gear_h + magnet_offset + magnet_h;
function sensor_z() = magnet_top() + sensor_gap + as5600_chip_top(); // pcb back face, board is chip down

// ----------------------------------------------------------------------------------------
function sensor_floor_z() = sensor_z() - as5600_pcb.z - sensor_standoff; // pocket floor

// wire channel centre in y, inside the fairing's innermost wall (+Y, sled r = 33/2), moved towards the pinion
function wire_channel_y() = 33/2 - fairing_t/2 - wire_channel.y/2 - wire_channel_shift;


// conduit around the channel, from the lower sled up to the plate, joined to the fairing wall behind it
module wire_conduit() {
    front_y = wire_channel_y() - wire_channel.y/2 - fairing_t;
    assert(front_y > outer_radius(mod=gear_mod, teeth=pinion_teeth, profile_shift=pinion_shift) + 0.5,
           "wire_conduit: wire_channel_shift too big, conduit hits the pinion");

    linear_extrude(upper_sled_z)
    intersection() {
        sled_profile();
        back(front_y)
            rect([wire_channel.x + 2*fairing_t, 20], anchor=FRONT);
    }
}

// ----------------------------------------------------------------------------------------
// as5600 board chip down over the magnet
module sensor() {
    up(sensor_z())
    yrot(180)
    //as5600_board(headers=BOTTOM, right_angle=true);
    as5600_board();
}

// stilts from the pocket floor up to the chip-side face, pegs locate in the pcb holes
module sensor_stilts() {
    up(sensor_floor_z())
    as5600_hole_positions() {
        cyl(d=4.5, h=sensor_standoff + 0.01, anchor=BOTTOM, $fn=24);
        up(sensor_standoff)
        cyl(d=as5600_hole_d - sensor_peg_fit, h=as5600_pcb.z - 0.2, chamfer2=0.3, anchor=BOTTOM, $fn=24);
    }
}

// ring around the magnet from the pocket floor up to just under the board, keeps wires out of the gap
module sensor_guard() {
    up(sensor_floor_z())
    tube(id=guard_id, od=guard_id + 2*guard_t, h=sensor_standoff - guard_gap, anchor=BOTTOM, $fn=64*LOD);
}

// wires dropped straight down the channel, from the pocket floor to below the motor
module sensor_wires() {
    top = sensor_floor_z() + wire_d/2;
    bottom = -3 - n20_box.z - n20_can.z;
    for (i = [0 : wire_n - 1])
        color(["red", "black", "yellow", "green", "blue", "white"][i % 6])
        translate([(i - (wire_n - 1)/2) * wire_d, wire_channel_y(), bottom])
        cyl(d=wire_d, h=top - bottom, anchor=BOTTOM, $fn=12);
}


// ring gear tooth tips, from the collar centre (internal teeth: addendum reduced by the shift)
function ring_tip_r() = pitch_radius(mod=gear_mod, teeth=ring_gear_teeth) - gear_mod * (1 - pinion_shift);

// wall following the sled's outer profile, from the lower sled top (z=0) up to the upper sled,
// trimmed back where the ring gear passes
module fairing() {
    linear_extrude(upper_sled_z)
    intersection() {
        difference() {
            sled_profile();
            offset(r=-fairing_t)
                sled_profile();
        }
        back(pinion_dist())
            circle(r=ring_tip_r() - fairing_fit, $fn=256*LOD);
    }
}
// ----------------------------------------------------------------------------------------

// position at the bolr holes
module at_sled_holes(pionion_r=0) {
    //fwd(5)
    for (side=[-1, 1])
        left(13 * side)
            children();
}

module upper_sled(pionion_r=0) {
    difference() {
        union() {
            sled_shape(6, greater_d=collar_od()-6, pinion_hole_d=10);
            at_sled_holes()
                cyl(d=6, h=upper_sled_z, $fn=32*LOD, anchor=TOP);
            down(upper_sled_z) {
                fairing();
                wire_conduit();
                sensor_stilts();
                sensor_guard();
            }
        }

        // ring is centred on the collar centre, which is +Y pinion_dist() in the sled frame
        back(pinion_dist())
            down(upper_sled_z)
                inner_collar_ring(e=0.1);

        // pcb pocket, open at the top, floor low enough for wires under the board
        // the wire space under the board stops short of the collar ring groove, so nothing gets in
        difference() {
            pocket = [as5600_pcb.x + 2*sensor_fit, as5600_pcb.y + 2*sensor_fit];
            board_face = sensor_z() - as5600_pcb.z - upper_sled_z;
            union() {
                up(board_face)
                cuboid([pocket.x, pocket.y, 20],
                       rounding=1 + sensor_fit, edges="Z", anchor=BOTTOM, $fn=24*LOD);
                intersection() {
                    up(sensor_floor_z() - upper_sled_z)
                    cuboid([pocket.x, pocket.y, sensor_standoff + 0.01],
                           rounding=1 + sensor_fit, edges="Z", anchor=BOTTOM, $fn=24*LOD);
                    back(pinion_dist())
                    cyl(r=(collar_od() - 32)/2 - 0.1 - pocket_wall, h=50, $fn=512*LOD);
                }
            }
            down(upper_sled_z) {
                sensor_stilts();
                sensor_guard();
            }
        }

        // wire drop: from the pocket floor through the plate and down the inside of the fairing's inner wall
        translate([0, wire_channel_y(), -upper_sled_z - 0.1])
        cuboid([wire_channel.x, wire_channel.y, sensor_floor_z() + 0.2], anchor=BOTTOM);

        // angled run from under the board, below the pocket wall, down into the channel
        let(edge = as5600_pcb.y/2 + sensor_fit,
            floor_l = sensor_floor_z() - upper_sled_z,
            face_l = sensor_z() - as5600_pcb.z - upper_sled_z)
        hull() {
            translate([0, edge, floor_l])
            cuboid([wire_channel.x, 1, face_l - floor_l], anchor=BOTTOM+BACK);
            translate([0, wire_channel_y(), -3])
            cuboid([wire_channel.x, wire_channel.y, 0.01], anchor=BOTTOM);
        }
               
        up(2)
        at_sled_holes()
            self_tap_hole(gauge=4, length=18, screw_type=my_screw_no_head,
                  hole_type=HOLE_SNUG, anchor=TOP);
        
    }
}

// negative for a sharp  edges sitting on the rotation surface, so whatever it passes
//   - ratio: (lead edge : running edge)
//   - knee: pulls the bend towards the corner (0 = sharp knee, 1 = gentle)
//   - side_ang: the corner's inside angle between the rotation surface and the side face, so the
//     curve meets the side face tangent too

function rolling_interface_path(size, ratio=2, knee=0.3, side_ang=90) =
    let(u = [-1, 0],                              // along the rotation surface, into the part
        v = [-cos(side_ang), sin(side_ang)],      // along the side face, into the part
        n = [v.y, -v.x],                          // side face normal, out of the part
        curve = bezier_curve([ratio*size*u, ratio*size*knee*u, size*knee*v, size*v],
                             splinesteps=max(8, round(48*LOD))))
    concat(curve, [size*v + size*n, size*n + [0, -size], [-ratio*size, -size]]);

module rolling_interface(size, h, ratio=2, knee=0.3, side_ang=90) {
    linear_extrude(h)
    polygon(rolling_interface_path(size, ratio, knee, side_ang));
}

// side_ang for rolling_interface() at a frame from rotation_surface_frame(), given the side face's
// direction into the part
function rolling_side_ang(frame, side_dir) =
    let(u = point2d(apply(frame, [-1, 0, 0]) - apply(frame, [0, 0, 0])))
    vector_angle(u, side_dir);

// fob to press the home switch
module lower_sled_fob(h) {
    fob_centre = [0, -(base_id/2 - pinion_dist())]; // outer edge of the lower sled
    collar_centre = [0, pinion_dist()];

    difference() {
        intersection() {
            sled_shape(h);
            translate(fob_centre)
            cyl(d=fob_d, h=h, chamfer1=0.5, chamfer2=-fob_flare, anchor=BOTTOM, $fn=64*LOD);
        }

        // the two corners where the post meets the rotation surface, following them out up the flare
        corners = function(d) sort(circle_circle_intersection(d1=d, cp1=fob_centre, d2=base_id, cp2=collar_centre));
        body = corners(fob_d);
        top = corners(fob_d + 2*fob_flare);
        for (i = [0, 1]) {
            body_frame = rotation_surface_frame(body[i], collar_centre, fob_centre);
            top_frame = rotation_surface_frame(top[i], collar_centre, fob_centre);

            // side face is the post's circle, its tangent at the corner heading in towards the collar centre
            radial = body[i] - fob_centre;
            tangent = [-radial.y, radial.x];
            side_ang = rolling_side_ang(body_frame, (collar_centre - body[i]) * tangent > 0 ? tangent : -tangent);
            path = rolling_interface_path(fob_lead_in, side_ang=side_ang);

            multmatrix(body_frame)
            down(0.01)
            rolling_interface(fob_lead_in, h - fob_flare + 0.02, side_ang=side_ang);

            // up the flare the corner moves out, skin between the two (the cut is concave, so no hull)
            skin([rolling_interface_slice(path, body_frame, h - fob_flare),
                  rolling_interface_slice(path, top_frame, h + 0.01)], slices=0);
        }
    }
}

// rolling_interface_path() placed by frame at height z, as a ccw 3d profile for skin()
function rolling_interface_slice(path, frame, z) =
    path3d(ccw_polygon(path2d(apply(frame, path3d(path)))), z);

// frame on point p of a rotation surface centred on centre: local X along its tangent, +Y towards centre,
// flipped so -X faces inside (a point in the part) when given
function rotation_surface_frame(p, centre, inside) =
    let(a = atan2(p.y - centre.y, p.x - centre.x) + 90,
        flip = is_def(inside) && (inside - p) * [cos(a), sin(a)] > 0)
    move(p) * zrot(a) * (flip ? xflip() : ident(4));

module at_rotation_surface(p, centre, inside) {
    multmatrix(rotation_surface_frame(p, centre, inside))
    children();
}

module lower_sled(pionion_r=0) {
    render()
    difference() {
        union() {
            sled_shape(lower_sled_h);
            down(fob_h)
            lower_sled_fob(fob_h);
        }

        // wire drop, under the fairing channel
        back(wire_channel_y())
        cuboid([wire_channel.x, wire_channel.y, 10]);

        // outer corners sit on the rotation surface, give them the same lead-in as the fob
        for (s = [-1, 1]) {
            p = sled_slice_point(s);
            frame = rotation_surface_frame(p, [0, pinion_dist()], [0, 0]);
            side_ang = rolling_side_ang(frame, sled_tangent_point(s) - p);

            multmatrix(frame)
            down(0.01)
            rolling_interface(sled_lead_in, lower_sled_h + 0.02, side_ang=side_ang);
        }

        at_sled_holes()
            yrot(180)
                self_tap_hole(gauge=4, length=18, screw_type=my_screw,
                    hole_type=HOLE_SNUG, anchor=TOP);
    }
}

module sled_assembly(pionion_r=0) {
    down(lower_sled_h)
        n20_motor();
    pinion(gear_spin=pionion_r);

    down(lower_sled_h)
    lower_sled();
    
    
    //up(upper_sled_z)
    //upper_sled(pionion_r);
    
    //sensor();
    //sensor_wires();
}


// ----------------------------------------------------------------------------------------
// Render
// ----------------------------------------------------------------------------------------


part = 0;

// full assembly
if(part == 0) {
    base();
    position_home_switch()
        d2f_switch(lever=false);
    #position_home_switch()
        home_switch_plug();
    //up(base_h)
    //collar();
    
    

    up(base_h)
    for(angle = [0, 120, 240]) {
        at_pinion(angle)
            sled_assembly(pionion_r=pinion_spin(angle));
        // pinion_at(angle);
    }

    // 25mm cube for scale
    //right(base_od/2 + 10)
        //cuboid(25, anchor=BOTTOM);
}

if(part == 1) {
    base();
}

if(part == 2) {
    collar();
}

if(part == 4) {
    pinion();
}

if(part == 5) {
    sled_assembly();
}

// home switch plug, top face down on the bed
if(part == 6) {
    up(base_h - home_switch_z())
        xrot(-90) // switch frame +Y (up) -> -Z, top face down
            home_switch_plug();
}

// test print: just the base around the home switch pocket, for fitting the switch and plug
if(part == -2) {
    test = [25, 30, 15]; // radial (from the bore), tangential, height (down from the base top)

    //down(base_h - test.z) left(base_id/2 - 1)
    
    render()
    intersection() {
        zrot(-home_switch_a)
            base();
        translate([base_id/2 - 5, 0, base_h - test.z])
            cuboid(test, anchor=LEFT+BOTTOM);
    }

}


// Demos and tests

if(part == -2) {
  // just the secion of the base with the mico pocket and the plug. 
  // layed out for 3d printing
}





