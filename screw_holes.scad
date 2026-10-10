// library for screw holes that meshes with my available
// hardware and opinions on holes.
/**
 *  Handles holes for self tapping screws in 3d printing.
 *
 *  Why create yet another library for this?
 *    - Needed better tolerances to common brand self tapping screws.
 *    - Wanted more complex hole geometry.
 *    - I felt existing libs were not sparking joy, so I wanted to
 *      dial in my own settings.
 *    - Seemed like a fun thing to do.
 *
 *  I was having issues with common brand screws being a bit different to
 *  UTS standards. IDK if this is just manufacturer measurement liberties or
 *  something more engineered to a goal.
 *
 *  Anyway: The result was not always getting a good fit making 3d printing
 *  parts.
 *
 *  My speculation, this seems to occur with manufacturers that specify
 *  a metric pilot hole. Perhaps they tweak the values to improve fit
 *  against common metric drill sizes?
 *
 *  Anyway I named the two sizes: "UK_GAUGE" and "UK_GAUGE_NARROW" (my
 *  observed slightly smaller screws).
 *
 *  Anyway, I found machinist tables online also vary. One of them
 *  seemed to very closely match my observed measurements:
 *   -https://www.thevintagescrewcompany.com/screw-size-guide/.
 *
 *  So I did a linear regression of that table (Removing a single outlier,
 *  possibly a typo in the table?) and got a fairly sensible formula for
 *  this "UK_GAUGE_NARROW".
 *
 *  Jargon:
 *    -  shank_dia: diameter of the screw's core, under the thread.
 *    - thread_dia: outer diameter across the thread crests.
 *    -   head_dia: diameter of the head.
 *    -     head_h: height of the head (the cone, for countersunk).
 *    -  pilot_dia: hole the screw taps its own thread into.
 *
 */
include <BOSL2/std.scad>

// Picks a power-of-two $fn so no facet edge is longer than max_segment_len.
function _auto_fn(d, max_segment_len = 0.5) =
    max(pow(2, ceil(log(d * PI / max_segment_len) / log(2))), 4);

SCREW_HEAD_COUNTERSUNK      = 2^1;
SCREW_HEAD_FLAT             = 2^2;
SCREW_HEAD_NONE             = 2^3;
SCREW_HEAD_SOCKET           = 2^4;  // SHCS

SCREW_UNIT_UK_GAUGE         = 2^5;
SCREW_UNIT_UK_GAUGE_NARROW  = 2^6;

// ie: a well made stainless steel screw (often called hinge screws on hardware store packet)
SCREW_FOR_HINGE             = 2^7;
SCREW_FOR_METAL             = 2^8;
SCREW_FOR_SOFT_WOOD         = 2^9;
SCREW_FOR_HARD_WOOD         = 2^10;


_HOLE_TWIST          = 2^10;  // modifier
HOLE_PILOT           = 2^1;   // tight fit
HOLE_SNUG            = 2^2;   // not a tight fit
HOLE_CLEARANCE       = 2^3;
HOLE_RIBBED          = 2^4;
HOLE_RIBBED_TWIST    = HOLE_RIBBED + _HOLE_TWIST;
HOLE_TRI             = 2^5;
HOLE_TRI_TWIST       = HOLE_TRI + _HOLE_TWIST;
HOLE_DROP            = 2^6;

function has_flag(flags, flag) =
    is_undef(flags) ? false : (floor(flags / flag) % 2) == 1;

// Standard formula for self tapping screws,
// ie: 0.33mm (ish) step starting from 1.52mm
function shank_size_uk(uk_gauge) =
    (0.06 + (uk_gauge* 0.013)) * 25.4;

// Formula obtained via regression of tables that lined up with what I could measure IRL
// ie: 0.36mm step starting from 1.3mm
function shank_size_uk_narrow(uk_gauge) =
   (0.36 * uk_gauge + 1.30);

function estimate_shank_from_gauge(gauge, screw_type) =
    (has_flag(screw_type, SCREW_UNIT_UK_GAUGE_NARROW)) ? shank_size_uk_narrow(gauge) :
    shank_size_uk(gauge);

// Most heads are 2x the shank, but that's not always the case
// - I have found some heads rounded to the nearest 0.5mm,
// - I have found some heads (13/6) ratio.
// - this function is for the worst-ish case.
function estimate_head_dia_from_shank(shank_dia, screw_type) =
    ceil(shank_dia * (13/6) * 2) / 2;
    //ceil(shank_dia * 2);

function estimate_head_h_from_head_dia(head_dia, screw_type) =
    (has_flag(screw_type, SCREW_HEAD_COUNTERSUNK)) ? 0.5 * head_dia :
    (has_flag(screw_type, SCREW_HEAD_FLAT)) ? 0.35 * head_dia :
    (has_flag(screw_type, SCREW_HEAD_SOCKET)) ? 0.75 * head_dia :
    (has_flag(screw_type, SCREW_HEAD_NONE)) ? 0 :
        0.35 * head_dia;

function estimate_thread_from_shank(shank_dia, screw_type) =
    (has_flag(screw_type, SCREW_FOR_HINGE)) ? 1.05 * shank_dia :
    (has_flag(screw_type, SCREW_FOR_METAL)) ? 1.08 * shank_dia:
    (has_flag(screw_type, SCREW_FOR_SOFT_WOOD)) ? 1.15 * shank_dia :
    (has_flag(screw_type, SCREW_FOR_HARD_WOOD)) ? 1.05 * shank_dia :
    1.1 * shank_dia;

function estimate_pilot_hole_dia(shank_dia, screw_type) =
    (has_flag(screw_type, SCREW_FOR_HINGE)) ? 0.75 * shank_dia :
    (has_flag(screw_type, SCREW_FOR_METAL)) ? 0.85 * shank_dia:
    (has_flag(screw_type, SCREW_FOR_SOFT_WOOD)) ? 0.65 * shank_dia :
    (has_flag(screw_type, SCREW_FOR_HARD_WOOD)) ? 0.75 * shank_dia :
    0.75 * shank_dia;


// The user can spec the screw how they want, this fills in the blanks.
// returns: [shank_dia, thread_dia, head_dia, head_h, pilot_dia]
function _resolve_screw_params(gauge=undef,
                               screw_type=undef,
                               shank_dia=undef,
                               thread_dia=undef,
                               head_dia=undef,
                               head_h=undef,
                               pilot_dia=undef
                               ) =
       let(shank_dia = is_undef(shank_dia) ?
                            estimate_shank_from_gauge(gauge, screw_type) :
                            shank_dia)

       let(thread_dia = is_undef(thread_dia) ?
                            estimate_thread_from_shank(shank_dia, screw_type) :
                            thread_dia)

       let(head_dia = is_undef(head_dia) ?
                            estimate_head_dia_from_shank(shank_dia, screw_type) :
                            head_dia)

       let(head_h = is_undef(head_h) ?
                            estimate_head_h_from_head_dia(head_dia, screw_type) :
                            head_h)

       let(pilot_dia = is_undef(pilot_dia) ?
                            estimate_pilot_hole_dia(shank_dia, screw_type) :
                            pilot_dia)

       [shank_dia, thread_dia, head_dia, head_h, pilot_dia];


module _head(head_dia, head_h, screw_type, sink, $fn) {
    sink = is_undef(sink) ? 0 : sink;
    if (has_flag(screw_type, SCREW_HEAD_COUNTERSUNK)) {
        flat_area_h = head_h*0.05; // 5% flat area on top.

        down(flat_area_h) {
            cyl(d=head_dia, h=flat_area_h, anchor=BOTTOM, $fn=$fn);
            cyl(d1=0, d2=head_dia, h=head_h, anchor=TOP, $fn=$fn);
        }
        if (sink > 0) {
            cyl(d=head_dia, h=sink, anchor=BOTTOM, $fn=$fn);
        }
    }
    if (has_flag(screw_type, SCREW_HEAD_FLAT) ||
        has_flag(screw_type, SCREW_HEAD_SOCKET)) {
        cyl(d=head_dia, h=head_h, anchor=BOTTOM, $fn=$fn);

        if (sink > 0) {
            up(head_h)
                cyl(d=head_dia, h=sink, anchor=BOTTOM, $fn=$fn);
        }
    }


    //if (has_flag(screw_type, SCREW_HEAD_NONE)) [
    //  grub screw > no operation
    //}

}

module _hole_shape_2d(hole_type, shank_dia, thread_dia, pilot_dia, $fn) {
    a = min(thread_dia, shank_dia);
    b = max(thread_dia, shank_dia);
    snug_dia = (a + (b-a)/2);
    clearance_dia = (1.2 * b) + 0.1;

    if (has_flag(hole_type, HOLE_PILOT)) {
        circle(d=pilot_dia, $fn=$fn);
    }
    if (has_flag(hole_type, HOLE_SNUG)) {

        circle(d=snug_dia, $fn=$fn);
    }
    if (has_flag(hole_type, HOLE_CLEARANCE)) {
        circle(d=clearance_dia, $fn=$fn);
    }
    if (has_flag(hole_type, HOLE_RIBBED)) {
        difference() {
            circle(d=b, $fn=$fn);
            r2 = (b-pilot_dia) / 2;
            left(b/2)
                circle(r=r2, $fn=$fn/2);
            rotate([0,0, 120])
                left(b/2)
                circle(r=r2, $fn=$fn/2);
            rotate([0,0, 240])
                left(b/2)
                circle(r=r2, $fn=$fn/2);
        }
    }
    if (has_flag(hole_type, HOLE_TRI)) {
        regular_ngon(n=3, id=pilot_dia, rounding=pilot_dia/6, align_tip=[0, 1]);
    }
    if (has_flag(hole_type, HOLE_DROP)) {
        teardrop2d(d=shank_dia, cap_h=shank_dia*0.65, $fn=$fn);
    }
}


module self_tap_hole(gauge=undef,
                     length,
                     hole_type=HOLE_PILOT,
                     sink=undef,
                     screw_type=undef,

                     shank_dia=undef,
                     thread_dia=undef,
                     head_dia=undef,
                     head_h=undef,
                     pilot_dia=undef,

                     anchor=undef,
                     dilate_head = 0.1,
                     $fn
              )
{
    // Position notes:
    //   - Button type screw hole is rendered with the base of the head at z=0;
    //   - countersunk is rendered with the top of the head at z=0;
    //   - this way z=0 means "top of surface with screw";
    //   - this can be overridden using anchor.
    //
    //  assuming countersunk screw length measured from the top of the head to the tip.
    assert(!is_undef(length), "A screw length is required.");
    assert(!(is_undef(gauge) && is_undef(shank_dia)) ,
           "A gauge size or shank_dia is needed.");

    // [shank_dia, thread_dia, head_dia, head_h, pilot_dia]
    params = _resolve_screw_params(gauge, screw_type, shank_dia, thread_dia,
                                   head_dia, head_h, pilot_dia);

    shank_dia = params[0];
    thread_dia = params[1];
    head_dia = params[2] + dilate_head;
    pilot_dia = params[4];
    sink = is_undef(sink) ? 0 : sink;

    // _head() only draws countersunk, flat and socket heads. With no head
    // there is no head height, and the shaft has to reach the surface itself.
    no_head = !has_flag(screw_type, SCREW_HEAD_COUNTERSUNK) &&
              !has_flag(screw_type, SCREW_HEAD_FLAT) &&
              !has_flag(screw_type, SCREW_HEAD_SOCKET);
    head_h = no_head ? 0 : params[3];
    shaft_h = length + (no_head ? sink : 0);

    hole_fn = is_undef($fn) ? _auto_fn(max(shank_dia, head_dia), 0.5) : $fn;

    shift = (anchor == TOP && !has_flag(screw_type, SCREW_HEAD_COUNTERSUNK)) ?
            sink + head_h :
            (anchor == BOTTOM) ?
                sink - length :
                sink;

    down(shift)
    {
        union() {
            //cyl(d=pilot_dia, h=length, anchor=TOP, $fn=hole_fn);
            //rotate([0, 180, 0])
            twist = has_flag(hole_type, _HOLE_TWIST) ? 180 * shaft_h / length : 0;
            down(length)
            linear_extrude(height = shaft_h, twist=twist)
                _hole_shape_2d(hole_type, shank_dia, thread_dia, pilot_dia, $fn=hole_fn);
            _head(head_dia, head_h, screw_type, sink=sink, $fn=hole_fn);
        }
    }
}


module test_board(gauge_type, gauge_name) {
    //my_screw = gauge_type + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_HARD_WOOD;
    my_screw = gauge_type + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_METAL;

    holes = [HOLE_PILOT, HOLE_SNUG, HOLE_CLEARANCE,
             HOLE_RIBBED, HOLE_RIBBED_TWIST,
             HOLE_TRI, HOLE_TRI_TWIST,
             HOLE_DROP];

    hole_names = ["pilot", "snug", "clear",
                  "  rib", "~rib~",
                  "  tri", "~tri~",
                  "drop"];

    gauges = [4,6,8,10];//,12,14];
    render()
    difference() {
        //down(15)
        cuboid([140, len(gauges)*15 + 12, 15],
                anchor=TOP+LEFT+FRONT, chamfer=1);

        for(g = [0:len(gauges)-1]) {
            gauge = gauges[g];
            back(g*15 + 5) {
                for(i = [0:len(holes)-1]) {
                    h_type = holes[i];
                    right((i) * 15 + 10)
                        back(5)
                        self_tap_hole(gauge=gauge, length=16,
                                      screw_type=my_screw, hole_type=h_type,
                                      anchor=TOP, sink=1);
                    }

                right(125)
                back(3)
                down(0.5)
                linear_extrude(height = 0.5)
                    text(str(gauge, "g"), size=5);
            } // end back

        } // end for(g=)

        // column labels
        for(i = [0:len(holes)-1]) {
            back(len(gauges)* 15 + 5)
            right(i*15 + 4)
            down(0.5)
            linear_extrude(height = 0.51)
                text(hole_names[i], size=4);
        }


        //title
        down(10)
        back(0.5)
        right(10)
        rotate([90, 0, 0])
        linear_extrude(height = 0.51)
            text(str("Test board: ", gauge_name), size=4);
    }
}

module _demo() {
    test_board(SCREW_UNIT_UK_GAUGE, "UK Gauge");

    //back(150)
    //    test_board(SCREW_UNIT_UK_GAUGE_NARROW, "UK Gauge (Narrow)");

    my_screw = SCREW_UNIT_UK_GAUGE + SCREW_HEAD_COUNTERSUNK + SCREW_FOR_HARD_WOOD;


    holes = [HOLE_PILOT, HOLE_SNUG, HOLE_CLEARANCE,
             HOLE_RIBBED, HOLE_RIBBED_TWIST,
             HOLE_TRI, HOLE_TRI_TWIST,
             HOLE_DROP];

    //self_tap_hole(gauge=4, length=16,
    //               screw_type=my_screw, hole_type=HOLE_TRI_TWIST,
    //               anchor=TOP, sink=1);
}

// Demo is not run on include; see examples/test_board.scad.

