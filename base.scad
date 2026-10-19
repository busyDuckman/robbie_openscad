include <sled.scad>

robbie_base = true; // turns off sled.scad's standalone view

/*
Vocab:
  base: tube on which robbie sits
  collar: the colar with an internal ring gear and channel for the sleds
*/

// ----------------------------------------------------------------------------------------
// Globals
// ----------------------------------------------------------------------------------------

function collar_holes_r() = 110/2; //half_way(collar_od(), base_id) / 2;
collar_holes_sa = 360/8/2; // half a step, so no screw sits over the cable hole / home switch

home_switch_a = 180;       // above the cable hole (-X)
home_switch_press = 0.25;  // fob pushes the plunger this far past its click point (d2f overtravel ~0.5)
home_switch_fit = 0.2;     // pocket clearance
home_switch_plug_fit = 0.05; // plug in the pocket
home_switch_plug_corner_r = 0.6; // rounds the plug's back corners, so the pocket's corners aren't the tight spot
home_switch_overcut = 2;   // pocket runs this far past the switch face into the bore, no thin base slivers
home_switch_drop = 1;      // the switch (top)  is below the lower sled + this
home_switch_retraction = 0.25; // the switch (front)  is retracted this far

home_switch_wedge = 1.5;   // plug is this much wider each side at the back than at the bore
home_switch_guard_min = 0.4; // thinnest base sliver kept in front of the switch as its forward guard
home_switch_solder_d = 3.2;  // room round each terminal for solder / etc
home_switch_wire_room = 3;   // extra pocket depth behind the terminals
home_switch_wire_w = 10;     // wire channel width (along the wall), drops straight down behind the terminals
home_switch_ledge_h = 6;     // depth of the ledges under the plug's fingers (they're 3.5 deep, so ~60 deg underside)


// ----------------------------------------------------------------------------------------
// Geometry
// ----------------------------------------------------------------------------------------

// base / collar join tabs: between the screws, none at the home switch, so the collar only fits one way round
module at_join_tabs() {
    for (a = [0 : 360/8 : 359])
        if (abs(posmod(a - home_switch_a + 180, 360) - 180) > 1) {
            zrot(a)
                right(collar_holes_r())
                    children();
        }
}

module base() {
    chamf = (collar_od() - base_id)/2;
    
    color("gray")
    
    render(convexity=10)
    difference() {
        union() {
            // outer top chamfer: chamf in, base_chamfer_h down (tube() has no chamfer angle, so cyl minus bore)
            cyl(d=base_od, h=base_h, chamfer2=chamf, chamfang2=atan(base_chamfer_h / chamf),
                anchor=BOTTOM, $fn=512*LOD);

            // alignment for the collar
            up(base_h - 0.01)
                at_join_tabs()
                    join_tab_male();
        }
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
    * move([base_id/2 + d2f_plunger_op_h - home_switch_press + home_switch_retraction, 0, home_switch_z()])
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
        if (corner_r > 0) {
            for (s = [-1, 1])
                translate([s * (back_w/2 - corner_r), y0, back_z + corner_r])
                    ycyl(r=corner_r, h=y1 - y0, anchor=FRONT, $fn=24);
        } else {
            translate([0, y0, back_z])
                cuboid([back_w, y1 - y0, 0.01], anchor=FRONT+BOTTOM);
        }

        translate([0, y0, front_z])
            cuboid([d2f_body.x + 2*c - 2*inset, y1 - y0, 0.01], anchor=FRONT+TOP);
    }
}

// negative: pocket for the lever-less d2f, open up through the base top, plunger hole out to the bore
module home_switch_holder() {
    c = home_switch_fit;
    up_open = base_h - home_switch_z() + 1; // switch +Y is up

    position_home_switch()
    difference() {
        union() {
        // body and terminals
        translate([0, -(d2f_body.y/2 + c), -d2f_pin.z])
            cuboid([d2f_body.x + 2*c, d2f_body.y + 2*c, d2f_pin.z + d2f_body.z + c], anchor=FRONT+BOTTOM);

        // extra room behind the terminals for wrapped wires and solder,
        // its ceiling slopes down at 45 deg from the plug's back edge (no flat overhang to print)
        hull() {
            translate([0, -(d2f_body.y/2 + c), -d2f_pin.z])
                cuboid([d2f_body.x + 2*c, d2f_body.y + 2*c, 0.01], anchor=FRONT+TOP);
            translate([0, -(d2f_body.y/2 + c), -(d2f_pin.z + home_switch_wire_room)])
                cuboid([d2f_body.x + 2*c, d2f_body.y + 2*c - home_switch_wire_room, 0.01], anchor=FRONT+BOTTOM);
        }

        // wire channel, straight down from behind the terminals and out the base bottom
        // (comes out into the cable hole, which is under the switch)
        translate([0, -(d2f_body.y/2 + c) + 0.01, -(d2f_pin.z + home_switch_wire_room)])
            cuboid([home_switch_wire_w, home_switch_z() + 1, d2f_pin.z + home_switch_wire_room],
                   anchor=BACK+BOTTOM);

        // in front of the switch the base is left as the forward guard: the slivers between the flat pocket
        // face and the curved bore. open the middle, where they'd be thinner than home_switch_guard_min
        // (measured from home_switch_a, which is at the plunger; clamped to the pocket's ends)
        let(face = base_id/2 + d2f_plunger_op_h - home_switch_press + home_switch_retraction - d2f_body.z - c, // pocket face from the axis
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

        // ledges for the plug's fingers to sit on, over the wire channel (the collar bolts down on the plug,
        // so they carry load), sloped underside home_switch_ledge_h deep against the channel's front wall
        for (x = [-1, 1] * d2f_pin_pitch/2)
            translate([x, -(d2f_body.y/2 + c), 0])
                hull() {
                    translate([0, 0, -d2f_pin.z])
                        cuboid([d2f_pin_pitch - home_switch_solder_d, 0.01, d2f_pin.z + 0.01], anchor=BACK+BOTTOM);
                    cuboid([d2f_pin_pitch - home_switch_solder_d, home_switch_ledge_h, 0.01], anchor=BACK+TOP);
                }
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



module collar() {
    color("blue")
    render(convexity=10)
    difference() {
        union() {
            tube(id=base_id, od=collar_od(), h=collar_h, anchor=BOTTOM, $fn=512*LOD);
            
            //outer collar
            tube(id=collar_od()-6, od=collar_od(), h=collar_h+3, anchor=BOTTOM, $fn=512*LOD);
            
            // inner collar
            inner_collar_ring(notches=true);
                
            up(gear_z_offset)
                ring_gear(mod=gear_mod, teeth=ring_gear_teeth , thickness=collar_gear_h, 
                          backing=10, profile_shift=pinion_shift,
                backlash=backlash, anchor=BOTTOM, $fn=512*LOD);
        }
    
        up(collar_h)
        zrot_copies(n=8, r=collar_holes_r(), sa=collar_holes_sa)
            self_tap_hole(gauge=my_screw_gauge, length=25, screw_type=my_screw,
                  hole_type=HOLE_CLEARANCE, anchor=TOP, sink=5);
          //cyl(h=20, d=6, $fn=64*LOD, anchor=BOTTOM);

        // alignment pits for the base's join tabs
        at_join_tabs()
            join_tab_female();
    }
          
}


// ----------------------------------------------------------------------------------------
module guide() {
    t = 3.0;
    tube(id = guide_id , od=guide_id +t+t, h=t, chamfer=0.25, $fn=128*LOD);
}


// ----------------------------------------------------------------------------------------
// debug: # tube over the ring gear's teeth (tip to root, gear height), to check sled clearance
module base_assembly(expand = 0, slice_mode = 0, view_mask=[], sled_view_mask=[], debug=false) {
    difference() {
        union() {
            if (debug) {
                up(20 * expand)
                    up(base_h + gear_z_offset)
                        #tube(ir=ring_tip_r(),
                              or=outer_radius(mod=gear_mod, teeth=ring_gear_teeth, internal=true, profile_shift=pinion_shift),
                              h=collar_gear_h, anchor=BOTTOM, $fn=256*LOD);
            }

            apply_view(view_mask[0])
                base();
            
            apply_view(view_mask[1])
                up(11 * expand)
                    position_home_switch()
                        d2f_switch(lever=false);
            
            apply_view(view_mask[2])
                up(18 * expand)
                    position_home_switch()
                        home_switch_plug();
            
                
            
            apply_view(view_mask[3])
                up(20 * expand)
                    up(base_h)
                        collar();
            


            apply_view(view_mask[4])
                up(50 * (expand*1.5))
                    up(base_h)
                        for(angle = [0, 120, 240]) {
                            at_pinion(angle)
                                sled_assembly(pionion_r=pinion_spin(angle), expand = max(0, expand - 0.5)*2, view_mask=sled_view_mask, debug=debug);
                        }
            
            
            apply_view(view_mask[5])
                up(50 * expand)
                    up(guide_h)
                        guide();
            
        }

        if (slice_mode == 1 || slice_mode == 3) {
            cuboid([400, 400, 400], anchor=BACK);
        }

        if (slice_mode == 2 || slice_mode == 3) {
            zrot(30)
                cuboid([400, 400, 400], anchor=BACK);
        }
    }
}

// ----------------------------------------------------------------------------------------
// Render
// ----------------------------------------------------------------------------------------
part = 0;
expand = 0; //0.5;     // 0 = assembeld, 0.5 = base expanded only, 1.0 = fully expanded. Can be animated.
slice_mode = 0; // cut the assembly: 0 none
                //   1 X/Z plane (y = 0, through the home switch plunger), keep +Y
                //   2 1 turned 30 CCW, through the angle 120 sled (at 30 deg), chops it in half
                //   3 both 1 and 2
print_layout=true;
debug = false;  // assembly debug aids (ring gear teeth tube)


// base view_mask:
//      0 base,         1 d2f switch,   2 plug,         3 collar,           4 sleds,
//      5 guide
//
// sled view_mask:
//      0 motor,        1 pinion,       2 magnet,       3 lower sled,       4 sled screws, 
//      5 upper sled,   6 sled top,     7 top screws,   8 biscuits,         9 sensor, 
//      10 screw/nut,   11 wire harness

base_collision_view = [0,0,0,1,1,0];
sled_collision_view = [0,1,0, 0,0,1, 0,0,1, 0,0,0];


view = base_collision_view ;   //[];
sled_view = sled_collision_view;   //[];

// full assembly
if(part == 0) {
    base_assembly(expand=expand, slice_mode=slice_mode, view_mask=view, sled_view_mask=sled_view, debug=debug);
}

// ----------------------------------------------------------------------------------------
// single parts, for export
//   positive: printed, negative: bought / not printed
//   raw, as modelled at the part's own origin, or print_layout = true to turn printed parts for the bed
//
//   100+: misc setups (sub assemblies, test prints)
//
//    1 base               -1 d2f switch           100 sled assembly
//    2 collar             -3 n20 motor            101 base test slice (home switch pocket)
//    3 guide              -4 as5600 board
//    4 pinion             -5 bearing screw (m3 x 25)
//    6 home switch plug   -6 bearing nut (m3)
//    7 lower sled         -7 sled screws (6g x 16)
//    8 upper sled         -8 wire harness
//    9 sled top           -9 magnet
//   10 sled biscuit

// printed parts: on the bed when print_layout (turned xrot then yrot, then lifted onto z=0), raw otherwise
module print_layout(xrot=0, yrot=0, lift=0) {
    if (print_layout) {
        up(lift)
            yrot(yrot)
                xrot(xrot)
                    children();
    } else {
        children();
    }
}

if(part == 1) {
    print_layout()
        base();
}

if(part == 2) {
    print_layout()
        collar();
}

// centred tube
if(part == 3) {
    print_layout(lift=3/2)
        guide();
}

if(part == 4) {
    print_layout()
        pinion();
}

// top face down (switch frame +Y is up)
if(part == 6) {
    print_layout(xrot=-90, lift=base_h - home_switch_z())
        home_switch_plug();
}

// top face down, join tab pits on the bed
if(part == 7) {
    print_layout(xrot=180, lift=lower_sled_h)
        lower_sled();
}

// plate top down, join tabs pointing up
if(part == 8) {
    print_layout(xrot=180, lift=upper_sled_h)
        upper_sled();
}

if(part == 9) {
    print_layout()
        sled_top();
}

// lying flat, layers across the joint
if(part == 10) {
    print_layout(yrot=90, lift=sled_biscuit.x/2)
        sled_biscuit();
}

if(part == -1) {
    d2f_switch(lever=false);
}

if(part == -3) {
    n20_motor();
}

if(part == -4) {
    as5600_board();
}

if(part == -5) {
    bearing_screw();
}

if(part == -6) {
    bearing_nut();
}

if(part == -7) {
    sled_screw();
}


if(part == -9) {
    magnet();
}

if(part == -8) {
    wire_harness();
}

if(part == 100) {
    sled_assembly();
}

// test print: just the base around the home switch pocket, for fitting the switch and plug
if(part == 101) {
    test = [25, 30, 15]; // radial (from the bore), tangential, height (down from the base top)

    //down(base_h - test.z) left(base_id/2 - 1)
    
    render(convexity=10)
    intersection() {
        zrot(-home_switch_a)
            base();
        translate([base_id/2 - 5, 0, base_h - test.z])
            cuboid(test, anchor=LEFT+BOTTOM);
    }

}







