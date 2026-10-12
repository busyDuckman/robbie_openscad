include <BOSL2/std.scad>

/*
Stand-ins for bought parts, accurate enough to model mounts around.
Use include <components.scad> so the size variables come through.
*/


// GA12-N20 gear motor stand-in, sizes from seller drawing
// origin at gearbox front face, shaft along +Z, body below (so at_pinion(a) n20_motor() works)
n20_box = [12, 10, 9];      // gearbox width, height, length
n20_can = [12, 10, 15.2];   // can diameter, across flats, length (incl. end cap)
n20_shaft = [3, 2.5, 10];   // diameter, across flat, length (length not on drawing, measure)

// clearance grows the gearbox and can (not the shaft) for use as a cutter
module n20_motor(clearance=0) {
    c = clearance;

    // gearbox, solid for csg
    color("gold")
    cuboid([n20_box.x + 2*c, n20_box.y + 2*c, n20_box.z], rounding=0.5 + c, edges="Z", anchor=TOP, $fn=16);

    // can, round with two flats
    color("silver")
    down(n20_box.z)
    intersection() {
        cyl(d=n20_can.x + 2*c, h=n20_can.z, anchor=TOP, $fn=64);
        cuboid([n20_can.x + 2*c, n20_can.y + 2*c, n20_can.z], anchor=TOP);
    }

    // D shaft, flat on +Y
    color("lightgray")
    intersection() {
        cyl(d=n20_shaft.x, h=n20_shaft.z, anchor=BOTTOM, $fn=64);
        fwd((n20_shaft.x - n20_shaft.y)/2)
        cuboid([n20_shaft.x, n20_shaft.y, n20_shaft.z], anchor=BOTTOM);
    }
}


// ultra-miniature lever snap switch stand-in (Omron D2F-L size, the mouse-button type)
// origin at body centre of the terminal face, plunger face up (+Z), lever hinged at -X, tip at +X
d2f_body = [12.8, 5.8, 6.5];   // length, thickness, height to the plunger face
d2f_lever = [12.5, 3, 0.3];    // length, width, thickness (measure)
d2f_lever_free_h = 10;         // lever tip height above the terminal face when free
d2f_lever_op_h = 6.8;          // lever tip height when it clicks (datasheet +-1.5, measure)
// sizes from reference_images/G1003-150P00A-PCB-Best-Mouse-Micro-Switch-1-2.png
d2f_plunger = [1.15, 2.9];     // button along the length, across the thickness, round topped
d2f_plunger_x = 3.15 + 5.20 - 12.8/2; // button centre from the body centre, towards +X (hole 3.15 in, then 5.20)
d2f_plunger_free_h = 7.3;      // button top above the terminal face when free (scaled off drawing, measure)
d2f_plunger_op_h = 6.9;        // button top when it clicks (not on drawing, measure; overtravel ~0.5 past this)
d2f_pin = [0.9, 0.6, 3.5];     // terminal blade width, thickness, length
d2f_pin_pitch = 5.08;          // 3 terminals, centred
d2f_hole_d = 2;                // mounting holes through the thickness
d2f_hole_spacing = 6.5;        // centred along the length
d2f_hole_z = 1.9;              // hole centre above the terminal face (scaled off drawing, measure)

// children at each mounting hole centre, run them along Y to go through the body
module d2f_hole_positions() {
    up(d2f_hole_z)
    xcopies(spacing=d2f_hole_spacing, n=2)
    children();
}

// clearance grows the body and plunger (not the lever or pins) for use as a cutter
// lever=false for the lever removed, plunger only
module d2f_switch(clearance=0, lever=true) {
    c = clearance;

    color("#222")
    difference() {
        cuboid([d2f_body.x + 2*c, d2f_body.y + 2*c, d2f_body.z + 2*c], anchor=BOTTOM, $fn=16);
        if (c == 0)
            d2f_hole_positions()
                ycyl(d=d2f_hole_d, h=2*d2f_body.y, $fn=24);
    }

    // button at its free height, off centre towards +X
    color("red")
    translate([d2f_plunger_x, 0, d2f_body.z - 0.01])
    cuboid([d2f_plunger.x + 2*c, d2f_plunger.y + 2*c, d2f_plunger_free_h - d2f_body.z + 0.01],
           rounding=c == 0 ? d2f_plunger.x/2 - 0.01 : 0, edges=[TOP+LEFT, TOP+RIGHT], anchor=BOTTOM, $fn=16);

    // lever, from the hinge end up to the free tip
    if (lever) {
        lever_rise = d2f_lever_free_h - d2f_body.z - 0.5;
        color("silver")
        translate([-d2f_body.x/2 + 0.5, 0, d2f_body.z + 0.5])
        yrot(-atan(lever_rise / d2f_lever.x))
        cuboid(d2f_lever, anchor=BOTTOM+LEFT);
    }

    color("gold")
    xcopies(spacing=d2f_pin_pitch, n=3)
    cuboid(d2f_pin, anchor=TOP);
}


// AS5600 magnetic encoder board stand-in (the cheap 23mm square ones)
// origin at board centre, pcb bottom at z=0, chip on top (+Z)
// flip with yrot(180) to face the chip down onto a magnet
as5600_pcb = [23, 23, 1.6];    // width, depth, thickness (thickness not on listing, measure)
as5600_hole_d = 3;             // corner holes (measured)
as5600_hole_inset = (23 - 16) / 2;  // holes 15mm apart centre to centre (measured)
as5600_chip = [3.9, 4.9, 1.5]; // SOIC-8 body, legs along x
as5600_chip_leads = 6.0;       // SOIC-8 width across the leads
as5600_header_x = 7.62;        // header columns at +-x from centre (measure), 3 pins at -x, 4 at +x
header_pitch = 2.54;
header_body_h = 2.5;           // plastic spacer
header_pin = [0.64, 6, 3];     // square size, length past the spacer, tail into the pcb
header_via = [1.0, 1.7];       // plated hole, pad diameter

// height of the chip's top face above the pcb bottom, for setting the magnet gap
function as5600_chip_top() = as5600_pcb.z + as5600_chip.z;

module as5600_hole_positions() {
    s = as5600_pcb.x/2 - as5600_hole_inset;
    for (x = [-s, s], y = [-s, s])
        translate([x, y, 0])
            children();
}

// children at each header through hole, z=0 at pcb bottom (3 at -x, 4 at +x)
module as5600_via_positions() {
    for (h = [[-as5600_header_x, 3], [as5600_header_x, 4]])
        right(h[0])
            ycopies(spacing=header_pitch, n=h[1])
                children();
}

// one header strip of n pins along Y, pcb surface at z=0
// straight: spacer on the pcb, pins up
// right_angle: pins bend at half a pitch up and run out along +X through a spacer lying beside the bend
module header_strip(n, right_angle=false) {
    if (!right_angle) {
        color("#222")
        cuboid([header_pitch, n*header_pitch, header_body_h], chamfer=0.2, edges="Z", anchor=BOTTOM);

        color("gold")
        ycopies(spacing=header_pitch, n=n)
        down(header_pin.z)
        cuboid([header_pin.x, header_pin.x, header_pin.z + header_body_h + header_pin.y], anchor=BOTTOM);
    } else {
        bend_z = header_pitch/2;

        color("#222")
        right(header_pitch/2)
        cuboid([header_body_h, n*header_pitch, header_pitch], chamfer=0.2, edges="X", anchor=BOTTOM+LEFT);

        color("gold")
        ycopies(spacing=header_pitch, n=n) {
            down(header_pin.z)
            cuboid([header_pin.x, header_pin.x, header_pin.z + bend_z + header_pin.x/2], anchor=BOTTOM);

            translate([-header_pin.x/2, 0, bend_z])
            cuboid([header_pin.x + header_pitch/2 + header_body_h + header_pin.y, header_pin.x, header_pin.x], anchor=LEFT);
        }
    }
}

// clearance grows the pcb outline (not the holes or chip) for use as a cutter
// headers: undef for none, TOP for spacer on the chip side, BOTTOM for spacer on the back
// right_angle: headers bend 90 deg and point out past the board edges (+-X)
module as5600_board(clearance=0, headers, right_angle=false) {
    c = clearance;

    color("white")
    difference() {
        cuboid([as5600_pcb.x + 2*c, as5600_pcb.y + 2*c, as5600_pcb.z], rounding=1 + c, edges="Z", anchor=BOTTOM, $fn=16);
        as5600_hole_positions()
            cyl(d=as5600_hole_d, h=3*as5600_pcb.z, $fn=32);
        if (c == 0)
            as5600_via_positions()
                cyl(d=header_via.x, h=3*as5600_pcb.z, $fn=16);
    }

    // header pads, both faces
    if (c == 0)
        color("gold")
        as5600_via_positions()
        down(0.05)
        difference() {
            cyl(d=header_via.y, h=as5600_pcb.z + 0.1, anchor=BOTTOM, $fn=24);
            cyl(d=header_via.x, h=3*as5600_pcb.z, $fn=16);
        }

    // chip, legs along the long sides
    up(as5600_pcb.z) {
        color("lightgray")
        cuboid([as5600_chip_leads, as5600_chip.y - 1, 0.3], anchor=BOTTOM);

        color("#222")
        cuboid(as5600_chip, anchor=BOTTOM);
    }

    // mirror the -x column so right angle pins point outward
    if (headers == TOP)
        for (h = [[-as5600_header_x, 3], [as5600_header_x, 4]])
            translate([h[0], 0, as5600_pcb.z])
                mirror([h[0] < 0 ? 1 : 0, 0, 0])
                    header_strip(h[1], right_angle);

    if (headers == BOTTOM)
        for (h = [[-as5600_header_x, 3], [as5600_header_x, 4]])
            translate([h[0], 0, 0])
                zflip()
                    mirror([h[0] < 0 ? 1 : 0, 0, 0])
                        header_strip(h[1], right_angle);
}
