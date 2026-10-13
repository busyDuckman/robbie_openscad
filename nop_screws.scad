/*
NopSCADlib screws, for the assembly views. Load with use <nop_screws.scad>, not include:
NopSCADlib's screw() would clash with BOSL2's, and use keeps it in here.
(use only brings modules through, so wrap each screw type in its own module)
*/
include <NopSCADlib/core.scad>
include <NopSCADlib/vitamins/screws.scad>

// No6 (6g) countersunk wood / self tapping screw, head top on z=0, shank down -Z
module no6_cs_screw(length) {
    screw(No6_cs_screw, length);
}
