include <BOSL2/std.scad>

/*
Small reusable bits. Use include <helpers.scad>.
*/


// ----------------------------------------------------------------------------------------
// Join tabs: alignment between two stacked parts (e.g. base and collar)
//   male:   flat topped, steep walled cone standing up off the lower part's top face
//   female: matching pit cut up into the upper part's bottom face, a little wider (fit) and
//           deeper (gap), so the walls locate it and the male's top never bottoms out
//   the pit's roof is a small flat circle, printed as a bridge with the upper part bottom-down
// ----------------------------------------------------------------------------------------

join_tab_d = 6;       // base diameter of the male
join_tab_h = 2.5;     // male height
join_tab_ang = 70;    // wall angle up from horizontal, steep so it locates, < 90 so it self-centres
join_tab_fit = 0.15;  // female wider than the male, each side
join_tab_gap = 0.4;   // female deeper than the male, air gap over its top

// diameter across the flat top of a join tab cone, d at its base, h tall
function join_tab_top_d(d=join_tab_d, h=join_tab_h, ang=join_tab_ang) = d - 2*h/tan(ang);

// male, base on z=0, standing up +Z
module join_tab_male(d=join_tab_d, h=join_tab_h, ang=join_tab_ang) {
    assert(join_tab_top_d(d, h, ang) > 0, "join_tab_male: too tall for its base and angle, no flat top left");

    cyl(d1=d, d2=join_tab_top_d(d, h, ang), h=h, anchor=BOTTOM, $fn=48);
}

// female cutter, mouth on z=0, going up +Z into the part above
module join_tab_female(d=join_tab_d, h=join_tab_h, ang=join_tab_ang, fit=join_tab_fit, gap=join_tab_gap) {
    mouth_d = d + 2*fit;
    depth = h + gap;
    assert(join_tab_top_d(mouth_d, depth, ang) > 0, "join_tab_female: too deep for its mouth and angle, no roof left");

    down(0.01)
        cyl(d1=mouth_d, d2=join_tab_top_d(mouth_d, depth, ang), h=depth + 0.01, anchor=BOTTOM, $fn=48);
}
