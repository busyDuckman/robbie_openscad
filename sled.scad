include <robbie_common.scad>

/*
The sleds: the three motor carriages that ride the collar's ring gear. Included by base.scad,
or open on its own (sled_view below) to work on just the sled.
Frame: z=0 at the collar bottom, origin on the pinion axis, +Y towards the collar centre.
*/

// ----------------------------------------------------------------------------------------
// Globals
// ----------------------------------------------------------------------------------------

upper_sled_z = collar_h; // upper sled bottom above the collar bottom: it rides on the collar top
upper_sled_h = 6;  
lower_sled_h = 3;  // lower sled thickness, hangs below the collar bottom

sled_r = 33/2;     // radius of the sled's round end, around the pinion

pinion_shaft_fit = 0.0; // added to the n20 D hole, 0 = nominal (press fit on X1C 0.2 nozzle), + looser, - tighter
gear_z_offset=1; // height offset so gears dont un on sled surface
motor_shaft_gap = 0.5;   // n20 shaft tip below the magnet
motor_pocket_fit = 0.1;  // snug pocket in the lower sled for the top of the n20 gearbox

magnet_d = 5.98; //ie should fit a 6mm hole
magnet_h = 2.5; //ie should fit a 6mm hole
magnet_offset = 1.0; // adjust to set magnet strength

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

sled_top_h = 4;        // sled_top plate thickness
sled_pin = [1.75, 5];  // sled_top / upper_sled alignment pins (filament offcut): diameter, length
top_sled_screw_l = 9; // 6g countersunk, sled_top to upper_sled (9 or 12)

sled_tab_d = 3;    // upper / lower sled join tabs (helpers.scad join_tab_*)
sled_tab_h = 1.2;

// ----------------------------------------------------------------------------------------
// Geometry
// ----------------------------------------------------------------------------------------

module pinion(gear_spin=0) {
    collar_od = magnet_d+4;
    
    color("orange")
    difference() {
        union() {
            up(collar_gear_h)
            //cyl(d=collar_od, h=magnet_offset, anchor=BOTTOM, $fn=128*LOD);
            tube(id=magnet_d-2, od=collar_od, h=magnet_offset, ochamfer1=-0.5, 
                 anchor=BOTTOM, $fn=128*LOD);
            
        
            up(collar_gear_h+magnet_offset)
            tube(id=magnet_d, od=collar_od, h=magnet_h, ochamfer2=0.25, 
                 anchor=BOTTOM, $fn=128*LOD);
        
            
            up(gear_z_offset)
            spur_gear(mod=gear_mod, teeth=pinion_teeth, thickness=collar_gear_h,
                    profile_shift=pinion_shift, backlash=backlash,
                    gear_spin=gear_spin, anchor=BOTTOM, $fn=128*LOD);
                    
            // lower boss/collar
            cyl(d=6, h=gear_z_offset, chamfer1=0.25, anchor=BOTTOM, $fn=128*LOD);

            }
            
        zrot(gear_spin)
            pinion_shaft_hole(collar_gear_h+gear_z_offset);

        // round part of the shaft, up to where its D flat starts
        down(0.01)
            cyl(d=n20_shaft.x + pinion_shaft_fit, h=motor_z() + n20_shaft.z - n20_shaft_d_len + 0.01, anchor=BOTTOM, $fn=64*LOD);
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

// where a sled side leaves the shaft circle (r = sled_r) on its way out to sled_slice_point()
function sled_tangent_point(s, slice_a = 45, slice_d = base_id) =
    let(r = sled_r,
        p = sled_slice_point(s, slice_a, slice_d),
        l = norm(p),
        phi = atan2(p.y, p.x))
    r * [cos(phi + s*acos(r/l)), sin(phi + s*acos(r/l))];

// 2D outline of sled_shape()
module sled_profile(pinion_hole_d, slice_a = 45, slice_d = base_id, greater_d) {
    greater_d = is_def(greater_d) ? greater_d : slice_d;
    r = sled_r;
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

// n20 gearbox face (motor origin) height: shaft tip motor_shaft_gap under the magnet's bottom
function motor_z() = collar_gear_h + magnet_offset - motor_shaft_gap - n20_shaft.z;
function sensor_z() = magnet_top() + sensor_gap + as5600_chip_top(); // pcb back face, board is chip down

// ----------------------------------------------------------------------------------------
function sensor_floor_z() = sensor_z() - as5600_pcb.z - sensor_standoff; // pocket floor

// wire channel centre in y, inside the fairing's innermost wall (+Y, sled_r), moved towards the pinion
function wire_channel_y() = sled_r - fairing_t/2 - wire_channel.y/2 - wire_channel_shift;


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

// round wire along a path of points, corners curved (bend, capped to half the shorter neighbour segment)
module wire_path(pts, bend=10) {
    joints = [for (k = [0 : len(pts) - 1])
                 k == 0 || k == len(pts) - 1 ? 0
                 : min(bend, norm(pts[k] - pts[k - 1])/2, norm(pts[k + 1] - pts[k])/2)];
    path = round_corners(pts, method="smooth", joint=joints, closed=false, $fn=16);

    for (i = [0 : len(path) - 2])
        hull() {
            translate(path[i])
                sphere(d=wire_d, $fn=8);
            translate(path[i + 1])
                sphere(d=wire_d, $fn=8);
        }
}

// 6 wire harness, in the sled frame, one row along X, motor wires on the ends, sensor vcc, gnd, sda, scl between
//   sensor wires: down the channel and the lower sled's 45 deg drop, then down the +Y zip tie post
//   motor wires: off the end cap, out to the same post and up beside them
//   the row runs in over the guide, drops through it and stops 5 under it
module wire_harness() {
    n = wire_n + 2;
    colours = ["blue", "red", "black", "yellow", "green", "white"];

    post_y = 5 + 3/2 + wire_d/2;                 // beside the +Y zip tie post (d3 at y=5)
    run_z = guide_h + 3/2 - base_h + 0.5 + wire_d/2; // just over the guide (3 thick, centred on guide_h)
    drop_y = pinion_dist() - 5;                  // drops through the guide 5 off the centre
    end_z = guide_h - 3/2 - 5 - base_h;          // 5 under the guide
    end_cap_z = motor_z() - n20_box.z - n20_can.z;

    for (j = [0 : n - 1]) {
        x = (j - (n - 1)/2) * wire_d;
        motor = j == 0 || j == n - 1;

        sled_pts = motor
            ? [[x, 2, end_cap_z + 0.5],
               [x, 2, end_cap_z - 1.5],
               [x, post_y, end_cap_z - 1.5],
               [x, post_y, run_z]]
            : [[x, wire_channel_y(), sensor_floor_z() + wire_d/2],
               [x, wire_channel_y(), 0],
               [x, post_y, -(wire_channel_y() - post_y)],
               [x, post_y, run_z]];

        color(colours[j])
        wire_path(concat(sled_pts,
                         [[x, drop_y, run_z],
                          [x, drop_y, end_z]]));
    }
}



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
// upper / lower sled join tabs, on the fairing either side of the conduit, centres in from the outer edge
module at_sled_tabs() {
    for (a = [45, 135])
        zrot(a)
            right(sled_r - 3)
                children();
}

module at_sled_holes(pionion_r=0) {
    //fwd(5)
    for (side=[-1, 1])
        left(12.5 * side)
            children();
}

// pcb pocket (negative, upper sled frame), open at the top, floor low enough for wires under the
// board, the stilts and magnet guard left standing in it
module sensor_pocket() {
    difference() {
        sensor_pocket_negative();
        down(upper_sled_z) {
            sensor_stilts();
            sensor_guard();
        }
    }
}

// The as5600_pcb board's pocket
//   - space for wires to run and a gaurd around the sensort to stop them interfearing.
//   - stops short of the collar ring groove.
module sensor_pocket_negative() {
    pocket = [as5600_pcb.x + 2*sensor_fit, as5600_pcb.y + 2*sensor_fit];
    board_face = sensor_z() - as5600_pcb.z - upper_sled_z;

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

module upper_sled(pionion_r=0) {
    difference() {
        union() {
            sled_shape(upper_sled_h, greater_d=collar_od()-6, pinion_hole_d=10);
            at_sled_holes()
                cyl(d=5.5, h=upper_sled_z, $fn=32*LOD, anchor=TOP);
            down(upper_sled_z) {
                fairing();
                wire_conduit();
                sensor_stilts();
                sensor_guard();

                // pads thickening the fairing round the tab pits
                at_sled_tabs()
                    cyl(d=6, h=upper_sled_z, anchor=BOTTOM, $fn=32*LOD);

                // join tabs, pointing down into the lower sled
                at_sled_tabs()
                    zflip()
                        join_tab_male(d=sled_tab_d, h=sled_tab_h);
            }
        }

        // ring is centred on the collar centre, which is +Y pinion_dist() in the sled frame
        back(pinion_dist())
            down(upper_sled_z)
                inner_collar_ring(e=0.1);

        sensor_pocket();

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
            self_tap_hole(gauge=6, length=18, screw_type=my_screw_no_head,
                  hole_type=HOLE_TRI_TWIST, anchor=TOP);

        // sled_top screws, sled_top_h of the screw is in the sled_top
        up(upper_sled_h)
            at_top_sled_holes()
                self_tap_hole(gauge=6, length=top_sled_screw_l - sled_top_h, screw_type=my_screw_no_head,
                    hole_type=HOLE_TRI_TWIST, anchor=TOP);

        up(upper_sled_h)
            at_sled_pins()
                zflip()
                    sled_pin_hole();
        
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

module engine_zip_tie_posts() {
    union() {
        difference() {
            cyl(d=12, h=22, chamfer2=-2, anchor=TOP, $fn=64*LOD);
            cuboid([30,10, 50], anchor=TOP);
        }
        
        //back(5)
        //cyl(d=3, h=22, chamfer2=-2, anchor=TOP, $fn=32*LOD);
        fwd(5)
        cyl(d=6.5, h=22, chamfer2=-2, anchor=TOP, $fn=64*LOD);
    }
}

module lower_sled(pionion_r=0) {
    render(convexity=10)
    difference() {
        union() {
            sled_shape(lower_sled_h, pinion_hole_d=n20_shaft.x + 0.4);
            down(fob_h)
                lower_sled_fob(fob_h);
                
            engine_zip_tie_posts();
        }

        // pits for the upper sled's join tabs
        up(lower_sled_h)
            at_sled_tabs()
                zflip()
                    join_tab_female(d=sled_tab_d, h=sled_tab_h);

        // wire drop, under the fairing channel, leaning 45 deg in towards the motor on the way down
        back(wire_channel_y())
            up(lower_sled_h)
                xrot(-45)
                    cuboid([wire_channel.x, wire_channel.y, 10], rounding=0.5, edges="Z", $fn=16);

        // snug pocket for the top of the n20 gearbox, up from the sled's underside,
        // square cornered so the gearbox's rounded corners sit loose and only the flats locate it
        up(motor_z() + lower_sled_h)
            cuboid([n20_box.x + 2*motor_pocket_fit, n20_box.y + 2*motor_pocket_fit, n20_box.z + n20_can.z], anchor=TOP);

        // outer corners sit on the rotation surface, give them the same lead-in as the fob
        for (s = [-1, 1]) {
            p = sled_slice_point(s);
            frame = rotation_surface_frame(p, [0, pinion_dist()], [0, 0]);
            side_ang = rolling_side_ang(frame, sled_tangent_point(s) - p);

            multmatrix(frame)
            down(0.01)
            rolling_interface(sled_lead_in, lower_sled_h + 0.02, side_ang=side_ang);
        }
        
        //there is a colllar befor the motor caft, this allws clerance.
        down(motor_z())
        cyl(d=6, h=0.5, anchor=BOTTOM, $fn=64*LOD);

        at_sled_holes()
            yrot(180)
                self_tap_hole(gauge=6, length=18, screw_type=my_screw,
                    hole_type=HOLE_CLEARANCE, anchor=TOP);
    }
}

module top_bearing(anchor=Front) {
    axle_h = 4;
    adj = anchor == FRONT ? 1 : -1;
    difference() {
        union() {
        up(axle_h)
            ycyl(d=10, h=7, chamfer=1, anchor=anchor, $fn=128*LOD);
            back(1 * adj) {
                //cuboid([10, 7-2, 8], rounding=4, edges=[TOP+LEFT, TOP+RIGHT],
                //    anchor=anchor+BOTTOM,  $fn=64*LOD);
                cuboid([10, 7-2, axle_h], rounding=-3,
                    edges=[BOTTOM], //edges=[BOTTOM+LEFT, BOTTOM+RIGHT],
                    anchor=anchor+BOTTOM,  $fn=128*LOD);
            }
        }

        // m3 x 25 machine screw through both, clearance
        up(axle_h)
            ycyl(d=3.4, h=20, $fn=32*LOD);

        // m3 nut capture on the inner one's (FRONT anchored, +Y) outer face, a point up so it prints
        if (anchor == FRONT)
            translate([0, 7 + 0.01, axle_h])
                xrot(-90)
                    zrot(90)
                        cyl(d=(5.5 + 0.3)/cos(30), h=3, anchor=TOP, $fn=6);
    }
}

// sled_top to upper_sled screws: either side of the outer bearing, on the strip past the collar
// ring channel (r 50.1 from the collar centre) to the sled's outer edge (r 125/2 - 3), midway across it
module at_top_sled_holes() {
    r = (50.1 + (collar_od() - 6)/2) / 2;
    for (x = [-11.5, 11.5])
        translate([x, pinion_dist() - sqrt(r*r - x*x), 0])
            children();
}

// sled_top / upper_sled alignment pins: inward (+Y), between the pcb pocket and the sled's edge
module at_sled_pins() {
    for (x = [-7, 7])
        translate([x, 13.4, 0])
            children();
}

// blind hole for half a pin (plus 0.5 slack), mouth on z=0, going up +Z
module sled_pin_hole() {
    down(0.01)
        cyl(d=sled_pin.x + 0.15, h=sled_pin.y/2 + 0.5 + 0.01, anchor=BOTTOM, $fn=16);
}

module sled_top() {
    color("blue")
    difference() {
        union() {
            sled_shape(sled_top_h, greater_d=collar_od()-6);
            fwd(3)
            up(sled_top_h) 
            {
                // NOTE: the front / back anchors mean the gap is defined easily regardless of cyl(h)
                top_bearing(anchor=FRONT);
                fwd(10)  // gap
                top_bearing(anchor=BACK);
            }
        }

        up(sled_top_h)
            at_top_sled_holes()
                self_tap_hole(gauge=6, length=top_sled_screw_l, screw_type=my_screw,
                    hole_type=HOLE_CLEARANCE, anchor=TOP);

        at_sled_pins()
            sled_pin_hole();
    }
}

// ----------------------------------------------------------------------------------------
// hardware, drawn at its own origin, placed (sled frame) by its at_*()

// 6g x 16 countersunk, head top on z=0, shank down -Z
module sled_screw() {
    no6_cs_screw(16);
}

// 6g countersunk, sled_top to upper_sled, head top on z=0, shank down -Z
module top_sled_screw() {
    no6_cs_screw(top_sled_screw_l);
}

// down through the sled_top into the upper sled, head flush with the sled_top's top face
module at_top_sled_screws() {
    up(upper_sled_z + upper_sled_h + sled_top_h)
        at_top_sled_holes()
            children();
}

// alignment pin, bottom on z=0
module sled_pin() {
    color("white")
    cyl(d=sled_pin.x, h=sled_pin.y, anchor=BOTTOM, $fn=16);
}

// centred on the sled_top / upper_sled joint
module at_sled_pins_hw() {
    up(upper_sled_z + upper_sled_h - sled_pin.y/2)
        at_sled_pins()
            children();
}

// as5600 diametric magnet, bottom on z=0
module magnet() {
    color("silver")
    cyl(d=magnet_d, h=magnet_h, anchor=BOTTOM, $fn=64*LOD);
}

// in the pinion's magnet cup
module at_magnet() {
    up(collar_gear_h + magnet_offset)
        children();
}

// up through the lower sled into the upper sled, head flush with the lower sled's underside
module at_sled_screws() {
    down(lower_sled_h)
        at_sled_holes()
            yrot(180)
                children();
}

// m3 x 25 pan head, head on z=0, shank down -Z
module bearing_screw() {
    screw("M3", length=25, head="pan", drive="phillips", atype="shaft", anchor=TOP, $fn=24);
}

// m3 nut, top face on z=0, body down -Z, a point along X
module bearing_nut() {
    nut("M3", anchor=TOP, $fn=24);
}

// through the top bearings (sled_top: up sled_top_h, axle 4 up), head on the outer face of the outer one
// (y = -3 - 10 - 7), shank along +Y
module at_bearing_screw() {
    up(upper_sled_z + upper_sled_h + sled_top_h + 4)
        fwd(3 + 10 + 7)
            xrot(90)
                children();
}

// in the inner bearing's trap (outer face y = -3 + 7), a point up
module at_bearing_nut() {
    up(upper_sled_z + upper_sled_h + sled_top_h + 4)
        back(-3 + 7)
            xrot(-90)
                zrot(90)
                    children();
}

module sled_assembly(pionion_r=0, expand = 0) {
    up(motor_z())
        n20_motor();
        
    up(32 * expand)
    pinion(gear_spin=pionion_r);

    // midway between the pinion's top (32 + 11.5) and the upper sled's fairing (50 + 0)
    up(36.5 * expand)
        at_magnet()
            magnet();

    up(30 * expand)
    down(lower_sled_h)
     lower_sled();

    up(10 * expand)
        at_sled_screws()
            sled_screw();
    
    
    up(50 * expand)
    up(upper_sled_z)
        upper_sled(pionion_r);
        
    
    up(70 * expand)
    up(upper_sled_z + upper_sled_h)
        sled_top();

    up(75 * expand)
        at_top_sled_screws()
            top_sled_screw();

    up(60 * expand)
        at_sled_pins_hw()
            sled_pin();

    
    up(60 * expand)
    sensor();
    
    up(80 * expand) {
        at_bearing_screw()
            bearing_screw();
        at_bearing_nut()
            bearing_nut();
    }
    
    
    wire_harness();
}



// ----------------------------------------------------------------------------------------
// Standalone view, only when sled.scad is opened directly (base.scad sets robbie_base)
// ----------------------------------------------------------------------------------------
sled_view = 1; // 0 none, 1 sled assembly, 2 lower sled, 3 upper sled, 4 sled top, 5 pinion

if (is_undef(robbie_base)) {
    if (sled_view == 1)
        sled_assembly();
    if (sled_view == 2)
        lower_sled();
    if (sled_view == 3)
        upper_sled();
    if (sled_view == 4)
        sled_top();
    if (sled_view == 5)
        pinion();
}
