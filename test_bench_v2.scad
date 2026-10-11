include <BOSL2/std.scad>
include <BOSL2/threading.scad>
include <BOSL2/rounding.scad>
include <components.scad>

/*
Hand-turned AS5600 test bench.
  - a dial with degree marks turns on a printed axle, read it against the pointer at the front
  - the magnet sits flush on a raised hub, the pocket fits the biggest magnet,
    printed inserts adapt smaller ones, and they store in labelled cups on the base
  - the encoder snaps under a bridge, chip down, centred over the magnet
  - the bridge rides dovetail rails and rests on a thumb wheel on a printed 1mm pitch screw,
    one turn = 1mm, the 4 notches = 0.25mm each, the big one under the needle on whole mm
  - solder the encoder headers on the back (headers=BOTTOM), dupont plugs drop into the bridge slots
*/

part = 0;
gap = 2;                // magnet top to chip face, for the assembly view

// printer tolerances, smaller = tighter
rail_fit = 0.15;         // bridge carriages on the dovetail rails, per side
thread_slop = 0.1;      // thumb wheel thread on the screw
axle_fit = 0.3;         // dial bore on the axle, on the diameter
magnet_fit = 0.05;      // added to magnet pocket diameters (press fit)
peg_fit = 0.1;          // bridge pegs in the AS5600 holes, on the diameter
clip_gap = 0.15;        // encoder clips to board edge

// magnets on hand, [diameter, thickness]
magnets = [[6, 2.5], [6, 3], [5, 2]];
push_hole_d = 1.4;      // push-out holes for a 1mm rod, under the dial pocket and through the inserts
big_d = max([for (m = magnets) m[0]]);
big_h = max([for (m = magnets) m[1]]);
pocket_d = big_d + magnet_fit;
inserts = [for (m = magnets) if (m[0] < big_d - 0.01 || m[1] < big_h - 0.01) m];

base_h = 4;
engrave = 0.6;
flare = 2.5;            // 45 deg feet on the screw and uprights

axle_d = 8;
axle_h = 5;

dial_d = 70;
dial_h = 8;
hub_d = 14;             // raised hub keeps the encoder clips clear of the dial
hub_h = 4;
dial_ccw = true;        // numbers count up turning anticlockwise (seen from above)
text_size = 4;

// insert storage cups on a lobe at the front left, title on a lobe at the front right
cup_pos = [-54, -28];
cup_pitch = 15;
title_pos = [46, -30];
base_fillet = 6;        // rounds the inside corners where the base lobes meet

// screw in line with the rails, right beside the dial (the wheel overhangs the dial edge, above it)
rod_d = 8;
rod_pitch = 1;          // one turn of the wheel = 1mm
rod_pos = [dial_d/2 + rod_d/2 + 1, 0];
rod_l = 38;
rod_bore = rod_d + 1;   // bridge hole over the threads

wheel_d = 26;
wheel_h = 6;
wheel_notches = 4;      // every 90 deg = 0.25mm, the big one lines up with the needle on whole mm

// measured: the printed nut mates, unturned, this far above a whole pitch from the rod bottom
// (re-measure if rod_d, rod_pitch, wheel_h or the thread $fn change)
thread_mate = 0.61;

upright = [8, 14];
rail_faces = [dial_d/2 + 9, rod_pos.x + wheel_d/2 + 10];   // -X and +X rail faces, carriages clear the dial and wheel
rail_w = [5, 8];        // width at the upright, width at the tip
rail_depth = 3;
carriage = [7.5, 16, 14]; // bridge block that wraps each rail, hangs down so it prints beam-down

beam_h = 4;
bar_w = 12;             // bridge bar between the rails, narrow so the wheel is easy to reach
ring_d = rod_bore + 6;  // bridge ring that rests on the wheel
standoff_h = 5;         // clears the header spacer on the back of the board

// snap clips on the +-Y edges of the board, fixed fences on the +-X edges
clip_w = 8;
clip_t = 1.0;
clip_root_r = 1.2;      // fillet at the clip root
hook_d = 0.6;
hook_h = 1.5;
fence_w = 6;
fence_t = 1.2;
beam_w = as5600_pcb.y + 2*(clip_gap + clip_t);

function dial_top() = base_h + dial_h;
function magnet_top() = dial_top() + hub_h;
function chip_z(gap) = magnet_top() + gap;
function beam_z(gap) = chip_z(gap) + as5600_chip_top() + standoff_h;
function mark_angle(a) = 270 + (dial_ccw ? -a : a);   // 0 at the pointer
function wheel_bottom(gap) = beam_z(gap) - wheel_h;
function wheel_turn(gap) = 360 * gap / rod_pitch;      // anticlockwise raises (right hand thread)

// lift the rod start so the nut mates with its big notch at the pointer when gap = 0
rod_z0 = base_h - 0.01;
rod_phase = posmod(wheel_bottom(0) - rod_z0 - thread_mate, rod_pitch);

// dovetail profile on the +X side with its face at x=fx, grown by f per side
function rail_profile(fx, f=0) = [
    [fx + f,              -(rail_w[0]/2 + f)],
    [fx + f,                rail_w[0]/2 + f],
    [fx - rail_depth - f,   rail_w[1]/2 + f],
    [fx - rail_depth - f, -(rail_w[1]/2 + f)]
];

// base outline: a disc under the dial, a bar along the rails, lobes for the cups and title,
// with the inside corners filleted
function base_region() =
    let(
        x0 = -(rail_faces[0] + upright.x + flare + 3),
        x1 = rail_faces[1] + upright.x + flare + 3,
        cups_w = max(1, len(inserts)) * cup_pitch + 6,
        shapes = union([
            circle(r=dial_d/2 + 7, $fn=128),
            move([(x0 + x1)/2, 0], rect([x1 - x0, upright.y + 2*flare + 6], rounding=8, $fn=32)),
            move(cup_pos + [(cups_w - cup_pitch - 6)/2, -2], rect([cups_w, 24], rounding=8, $fn=32)),
            move(title_pos, rect([40, 18], rounding=8, $fn=32))
        ])
    )
    offset(offset(shapes, r=base_fillet, closed=true), r=-base_fillet, closed=true);

// children once per rail, mirrored so that rail is on +X, with its face at x=$rail_x
module each_rail() {
    for (i = [0, 1])
        let($rail_x = rail_faces[i])
        mirror([i == 0 ? 1 : 0, 0, 0])
        children();
}


module bench_base() {
    color("gray")
    difference() {
        union() {
            offset_sweep(base_region(), height=base_h, top=os_circle(r=1.5), steps=6);

            up(base_h)
            cyl(d=axle_d, h=axle_h, chamfer2=0.5, anchor=BOTTOM, $fn=64);

            // pointer at the front, tip just off the dial rim, a little proud of the dial top,
            // a triangle with its back side (toward the user) curved to follow the base edge,
            // a rounded top edge, and a flared foot like the posts
            up(base_h - 0.01)
            let(pf = 1, r = dial_d/2 + 7 - pf - 0.5, half = asin(3 / r))
            offset_sweep(concat([[0, -dial_d/2 - 0.5]], arc(n=16, r=r, angle=[270 + half, 270 - half])),
                         height=dial_h + 1, top=os_circle(r=0.8), bottom=os_chamfer(width=-pf), steps=6);

            // screw, started one pitch down in the plate so its phase lines up the wheel notch
            translate(rod_pos) {
                up(rod_z0 + rod_phase - rod_pitch)
                threaded_rod(d=rod_d, l=rod_l + rod_pitch - rod_phase, pitch=rod_pitch, bevel2=true, anchor=BOTTOM, $fn=32);

                // flared foot so it survives a drawer
                up(base_h - 0.01)
                cyl(d1=rod_d + 2*flare, d2=rod_d, h=flare, anchor=BOTTOM, $fn=48);
            }

            // uprights with the dovetail rails, flared feet
            up(base_h - 0.01)
            each_rail() {
                translate([$rail_x, 0, 0])
                cuboid([upright.x, upright.y, rod_l], rounding=1.5, edges="Z", anchor=BOTTOM+LEFT, $fn=16);

                translate([$rail_x + upright.x/2, 0, 0])
                prismoid(size1=[upright.x + 2*flare, upright.y + 2*flare], size2=[upright.x, upright.y],
                         h=flare, rounding=1.5, anchor=BOTTOM, $fn=16);

                linear_extrude(rod_l)
                polygon(rail_profile($rail_x));
            }

            // storage cups for the magnet inserts
            // low, with two opposing finger slots so the adapters are easy to pick out
            for (i = idx(inserts))
                translate(cup_pos + [i * cup_pitch, 0])
                up(base_h - 0.01)
                difference() {
                    tube(od=pocket_d + 3, id=pocket_d + 0.3, h=1.5, ochamfer2=0.4, anchor=BOTTOM, $fn=48);
                    cuboid([pocket_d + 6, 4, 10], rounding=1, edges="Z", $fn=16);
                }
        }

        // push-out hole up through the base and axle, lines up with the one in the dial
        cyl(d=push_hole_d, h=3*(base_h + axle_h), $fn=16);

        // labels
        up(base_h - engrave) {
            for (i = idx(inserts))
                translate(cup_pos + [i * cup_pitch, -9])
                linear_extrude(1)
                text(str(inserts[i][0], "x", inserts[i][1]), size=3, halign="center", valign="center");

            translate(title_pos)
            linear_extrude(1)
            text("AS5600", size=6, halign="center", valign="center");
        }
    }
}

module dial_marks_2d() {
    r = dial_d/2 - 1;

    for (a = [0 : 5 : 355])
        let(len = a % 30 == 0 ? 6 : a % 10 == 0 ? 4 : 2.5)
        rot(mark_angle(a))
        right(r - len)
        rect([len, 0.6], anchor=LEFT);

    for (a = [0 : 30 : 330])
        rot(mark_angle(a))
        right(r - 6 - text_size)
        rot(90)
        text(str(a), size=text_size, halign="center", valign="center");
}

module dial() {
    color("orange")
    difference() {
        union() {
            // big chamfer underneath clears the screw's flared foot
            cyl(d=dial_d, h=dial_h, chamfer1=flare + 1, chamfer2=0.5, anchor=BOTTOM, $fn=128);
            up(dial_h)
            cyl(d=hub_d, h=hub_h, chamfer2=0.3, anchor=BOTTOM, $fn=64);
        }

        down(0.01)
        cyl(d=axle_d + axle_fit, h=axle_h + 0.5, anchor=BOTTOM, $fn=64);

        // magnet pocket, flush with the hub top, with a notch to pry it out
        up(dial_h + hub_h - big_h) {
            cyl(d=pocket_d, h=big_h + 1, anchor=BOTTOM, $fn=64);
            right(pocket_d/2)
            cuboid([2, 1.5, big_h + 1], anchor=BOTTOM);
        }

        // push-out hole from the axle bore up into the pocket (lift the dial off, poke a rod up)
        cyl(d=push_hole_d, h=3*(dial_h + hub_h), $fn=16);

        up(dial_h - engrave)
        linear_extrude(engrave + 1)
        dial_marks_2d();
    }
}

// adapts a smaller magnet to the pocket, its top sits flush with the hub
// with a push-out hole through the middle for a 1mm rod
module magnet_insert(m) {
    color("royalblue")
    difference() {
        if (m[0] < big_d - 0.01)
            difference() {
                cyl(d=pocket_d - 0.1, h=big_h, anchor=BOTTOM, $fn=64);
                up(big_h - m[1])
                cyl(d=m[0] + magnet_fit, h=m[1] + 1, anchor=BOTTOM, $fn=64);
            }
        else
            cyl(d=pocket_d - 0.1, h=big_h - m[1], anchor=BOTTOM, $fn=64);   // spacer under a thinner magnet

        cyl(d=push_hole_d, h=3*big_h, $fn=16);
    }
}

// an insert with its magnet in it, magnet top at big_h, explode lifts them apart for viewing
module magnet_in_insert(m, explode=0) {
    up(explode)
    magnet_insert(m);
    color("silver")
    up(big_h - m[1] + 2*explode)
    cyl(d=m[0], h=m[1], anchor=BOTTOM, $fn=48);
}

module thumb_wheel() {
    color("orange")
    difference() {
        cyl(d=wheel_d, h=wheel_h, chamfer=0.5, anchor=BOTTOM, $fn=96);

        // V notches on the side and lines across the top every 90 deg (0.25mm),
        // the big one at -Y sits under the bridge needle on whole mm
        for (i = [0 : wheel_notches - 1])
            let(a = 270 + i * 360 / wheel_notches, big = i == 0, s = big ? 3.5 : 1.8)
            rot(a) {
                right(wheel_d/2)
                zrot(45)
                cuboid([s, s, 3*wheel_h]);

                right(ring_d/2 + 0.5)
                up(wheel_h - engrave)
                cuboid([wheel_d/2 - ring_d/2, big ? 1.6 : 0.8, 1], anchor=BOTTOM+LEFT);
            }

        up(wheel_h/2)
        threaded_rod(d=rod_d, l=wheel_h + 0.2, pitch=rod_pitch, internal=true, $slop=thread_slop, $fn=32);
    }
}

// snap clips (+-Y) and fences (+-X) hanging from z=0, board back face at z=-standoff_h
module as5600_clips() {
    pcb_z = standoff_h + as5600_pcb.z;   // down to the chip-side face of the board

    yflip_copy() {
        back(as5600_pcb.y/2 + clip_gap)
        cuboid([clip_w, clip_t, pcb_z + hook_h], anchor=TOP+FRONT);

        // fillet where the clip meets the beam, spreads the bend so it doesn't snap off
        back(as5600_pcb.y/2 + clip_gap)
        rotate([90, 0, 90])
        linear_extrude(clip_w, center=true)
        difference() {
            translate([-clip_root_r, -clip_root_r]) square(clip_root_r);
            translate([-clip_root_r, -clip_root_r]) circle(r=clip_root_r, $fn=32);
        }

        // hook, flat top catches the board, slope underneath for lead-in
        down(pcb_z)
        back(as5600_pcb.y/2 + clip_gap)
        rotate([90, 0, 90])
        linear_extrude(clip_w, center=true)
        polygon([[0, 0], [-hook_d - clip_gap, 0], [0, -hook_h]]);
    }

    xflip_copy()
    right(as5600_pcb.x/2 + clip_gap)
    cuboid([fence_t, fence_w, standoff_h + as5600_pcb.z/2], anchor=TOP+LEFT);
}

// beam bottom at z=0, board hangs below on snap clips, a ring rests on the wheel at the screw
module bridge() {
    color("lightblue")
    difference() {
        union() {
            linear_extrude(beam_h) {
                // board block
                rect([as5600_pcb.x + 2, beam_w], rounding=2, $fn=16);

                // narrow bar out to the rails
                translate([(rail_faces[1] - rail_faces[0])/2, 0])
                rect([rail_faces[0] + rail_faces[1] - 1, bar_w], rounding=2, $fn=16);

                // ring on the wheel
                translate(rod_pos) circle(d=ring_d, $fn=48);
            }

            // short needle over the wheel top marks, top flush with the beam, just clear of the wheel
            translate(rod_pos)
            up(0.3)
            linear_extrude(beam_h - 0.3)
            hull() {
                circle(d=5, $fn=24);
                fwd(ring_d/2 + (wheel_d/2 - 1 - ring_d/2)/2) circle(d=1.6, $fn=16);
            }

            // carriage blocks that wrap the rails, hang down from the beam top
            each_rail()
            translate([$rail_x - 0.5, 0, beam_h])
            cuboid(carriage, rounding=1, edges="Z", anchor=TOP+RIGHT, $fn=16);

            // rests for the back of the board, with pegs that locate in its mounting holes
            as5600_hole_positions() {
                cyl(d=as5600_hole_d + 0.6, h=standoff_h, anchor=TOP, $fn=24);   // slim, clears the header spacers
                down(standoff_h)
                cyl(d=as5600_hole_d - peg_fit, h=as5600_pcb.z - 0.2, chamfer1=0.3, anchor=TOP, $fn=24);
            }

            as5600_clips();
        }

        translate(rod_pos) cyl(d=rod_bore, h=3*beam_h, $fn=32);

        each_rail()
        up(beam_h - carriage.z - 1)
        linear_extrude(carriage.z + 2)
        polygon(rail_profile($rail_x, rail_fit));

        // slots for the header pins and dupont plugs
        for (h = [[-as5600_header_x, 3], [as5600_header_x, 4]])
            translate([h[0], 0, 0])
            cuboid([header_pitch + 0.6, h[1]*header_pitch + 0.6, 3*beam_h]);

        up(beam_h - engrave)
        translate([(as5600_pcb.x/2 + 1 + rod_pos.x - ring_d/2)/2, 0])
        linear_extrude(1)
        text("1mm/turn", size=2.8, halign="center", valign="center");
    }
}

module bench_assembly(gap, turn=40) {
    bench_base();

    up(base_h)
    zrot(dial_ccw ? turn : -turn) {
        dial();
        color("silver")
        up(magnet_top() - base_h - big_h)
        cyl(d=big_d, h=big_h, anchor=BOTTOM, $fn=64);
    }

    // inserts stored in their cups, each with its magnet
    for (i = idx(inserts))
        translate(cup_pos + [i * cup_pitch, 0])
        up(base_h)
        magnet_in_insert(inserts[i], explode=5);

    translate(rod_pos)
    up(wheel_bottom(gap))
    zrot(wheel_turn(gap))
    thumb_wheel();

    up(beam_z(gap))
    bridge();

    up(chip_z(gap) + as5600_chip_top())
    xrot(180)
    as5600_board(headers=BOTTOM);
}


if (part == 0) bench_assembly(gap);
if (part == 1) bench_base();
if (part == 2) dial();
if (part == 3) xrot(180) bridge();   // print beam-down
if (part == 4) thumb_wheel();
if (part == 5)   // inserts for every magnet that isn't the biggest
    for (i = idx(inserts))
        right(i * (big_d + 4))
        magnet_insert(inserts[i]);
