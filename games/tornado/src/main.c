#include <genesis.h>
#include "tornado.h"

// CPC TORNADO -- fly a real route, side on.
//
// You pick a departure and a destination airport, and the game flies you the
// line between them in side view. The world scrolls past: other aircraft on the
// same corridor (real flight numbers, real data, pulled down the controller-port
// data cable from Pluto), arrows below with airport codes as you overfly them,
// and a city band along the bottom when you drop low.
//
// This file is the base of that: the plane, the sky, and the controls. Nothing
// is fetched yet. What matters now is that the frame it is built on is the right
// one, so the rest slots in rather than being retrofitted:
//
//   - A state machine, so a title screen and the airport picker are new states
//     rather than surgery on the flight loop.
//   - Distance measured as position ALONG A ROUTE, not as a scroll counter, so
//     "you are 140 miles out, that arrow is JFK" is a lookup and not a rewrite.
//   - BG_B is the far sky. BG_A is deliberately left empty and scrolling slower:
//     that is where the city band goes.

typedef enum
{
    ST_FLYING = 0,          // the only state today
    ST_TITLE,               // reserved: title / attract
    ST_PICKER               // reserved: choose departure and destination
} GameState;

// --- screen ---------------------------------------------------------------
#define SCR_W        320
#define SCR_H        224

// --- the plane ------------------------------------------------------------
// Positions are pixels; velocity is 16.8 fixed point, so the plane eases rather
// than jumping whole pixels per frame.
#define PLANE_W      120
#define PLANE_H      64

// Position AND velocity are 16.8 fixed point. Keeping the position fixed too
// matters: converting velocity to whole pixels every frame rounds toward
// negative infinity, so up drifted on the faintest nudge while down needed a
// full pixel of velocity before anything happened at all.
#define FIX_SHIFT    8
#define TO_FIX(v)    ((s32)(v) << FIX_SHIFT)
#define FROM_FIX(v)  ((s16)((v) >> FIX_SHIFT))

#define ACCEL_Y      28     // per frame while held
#define ACCEL_X      20
#define DRAG         14     // bleeds velocity back toward level flight
#define VEL_MAX_Y    TO_FIX(3)
#define VEL_MAX_X    TO_FIX(2)

// Flight box, kept clear of the very edges so the plane never half-leaves the
// screen, which reads as a bug even when it is not.
#define MIN_X        8
#define MAX_X        (SCR_W - PLANE_W - 8)
#define PLANE_Y      80     // pinned: the world moves vertically, not the plane

// --- altitude -------------------------------------------------------------
// Altitude is a SPACE you fly through, not a position on screen. Mapping the
// whole cruising band onto one screen was the mistake: everything was always in
// view, so there was nothing to look for. At 12 feet per pixel the band is
// roughly 3.7 screens tall, so an airliner 1500 feet above you is genuinely
// off-screen until you climb to its level.
#define ALT_MIN_FT   30000
#define ALT_MAX_FT   40000
#define FT_PER_PX    12
#define ALT_PX_MAX   ((ALT_MAX_FT - ALT_MIN_FT) / FT_PER_PX)

#define VS_ACCEL     20     // how hard the stick bites vertically
#define VS_DRAG      12
#define VS_MAX       TO_FIX(2)

#define SKY_BLUES    11     // palette entries 1..11 are sky; 12..14 are cloud

#define KT_CRUISE    480    // knots at rest
#define KT_PER_FIX   60     // knots per unit of throttle

// --- traffic --------------------------------------------------------------
// Opposing airliners on the same corridor. They sit at EVEN flight levels
// because we are heading east: under the cruising-level rules, eastbound
// traffic takes the odd levels and westbound the even ones, so everything you
// meet head-on is at an even level and never at yours.
#define TRAFFIC_N    3
#define AIRLINER_W   128    // wider than the Tornado, because an airliner is
#define AIRLINER_H   48
#define CLOSURE      3      // their groundspeed, added to ours as closing speed

// Three rows so the readouts can sit on rows 1 and 2, off the screen edge, and
// stacked in a corner instead of stretched across the top. Deliberately plain:
// this is an instrument, and the real HUD gets designed once it is settled what
// moves over to the GBA.
#define HUD_ROWS     3      // window plane height, in tiles
#define HUD_INK      0x00EE // yellow, the colour a Sonic HUD is expected in

// --- the route ------------------------------------------------------------
// The plane holds station and the world moves past it, which is what makes it
// read as cruising rather than as a sprite being dragged around.
//
// CRUISE_SPEED is the baseline. Throttling forward or back changes how fast the
// route is eaten, and later this is also where wind belongs: a headwind slows
// the route while the sky keeps moving.
#define CRUISE_SPEED 2
#define PARALLAX_DIV 3      // the city band drifts slower than the sky

static GameState state;

// Where Sonic stands, relative to the plane sprite's top-left corner. Measured
// off the art, not guessed: the upper wing's surface sits at y=8 spanning
// x=76..110, and Sonic's feet are the last opaque row of his 48px frame.
#define SONIC_OFF_X  75
#define SONIC_OFF_Y  (-39)

static Sprite *plane;
static Sprite *sonic;
static s32 plane_x;                 // fixed point
static s32 vel_x;                   // fixed point
static s32 alt_fix;                 // fixed-point pixels above ALT_MIN_FT
static s32 vs;                      // vertical speed, fixed point
static u16 sky_base[16];            // the sky palette as authored, untinted

typedef struct
{
    Sprite *spr;
    s32 x;                          // fixed point, screen space
    s16 alt_px;                     // its altitude, same units as alt_fix
} Traffic;

static Traffic traffic[TRAFFIC_N];
static u16 spawn_seq;

// Westbound cruising levels, in our altitude-pixel units.
#define FL_PX(ft)   (((ft) - ALT_MIN_FT) / FT_PER_PX)
static const s16 westbound_levels[] = {
    FL_PX(30000), FL_PX(32000), FL_PX(34000), FL_PX(36000), FL_PX(38000)
};
// Throttle is the airspeed you have asked for, and is deliberately NOT the same
// thing as vel_x, which is how fast the plane is sliding across the screen.
// Holding right against the front of the box means you have stopped sliding but
// have not throttled back, so the route should keep being eaten at full rate.
static s32 throttle;
static u32 route_pos;               // distance flown along the route
static s16 scroll_sky, scroll_gnd;

static void approach_zero(s32 *v, s32 amount)
{
    if (*v > 0) { *v -= amount; if (*v < 0) *v = 0; }
    else if (*v < 0) { *v += amount; if (*v > 0) *v = 0; }
}

static s32 clamp_fix(s32 v, s32 lo, s32 hi)
{
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
}

// The HUD lives on the window plane, which does not scroll - so it survives
// BG_A being handed over to the city band later without having to move.
static void hud_init(void)
{
    // A palette where every ink colour is white, so the font renders legibly
    // whichever index its glyphs happen to use.
    u16 hud_pal[16];
    u16 i;
    for (i = 0; i < 16; i++) hud_pal[i] = HUD_INK;
    hud_pal[0] = 0;
    PAL_setColors(PAL3 * 16, hud_pal, 16, DMA);

    VDP_setWindowVPos(FALSE, HUD_ROWS);
    VDP_setTextPlane(WINDOW);
    VDP_setTextPalette(PAL3);
    VDP_clearTextArea(0, 0, 40, HUD_ROWS);

    // Fixed furniture, drawn once; only the numbers are redrawn.
    VDP_drawText("ALT", 1, 1);
    VDP_drawText("FT", 11, 1);
    VDP_drawText("SPD", 1, 2);
    VDP_drawText("KT", 9, 2);
}

// The sky is one seamless, vertically-wrapping image, so it cannot carry
// "higher is darker" in its pixels. The palette carries it instead: the blues
// are pulled toward deep navy as you climb, while the cloud tones are left
// alone.
//
// Note this BLENDS toward a colour rather than scaling the channels. Scaling
// looks like the obvious way to darken, but with only 3 bits per channel it
// squeezes the gaps between them shut - (5,6,7) scaled by 0.8 becomes (4,4,5),
// red catches green, and what should be deep blue comes out slate green. Moving
// toward a chosen navy keeps blue ahead of the others the whole way down.
#define NAVY_R 0
#define NAVY_G 1
#define NAVY_B 4

static void sky_tint(void)
{
    u16 pal[16];
    u16 i;
    s32 k = (FROM_FIX(alt_fix) * 166) / ALT_PX_MAX;     // 0 low .. 166 high

    memcpy(pal, sky_base, sizeof(pal));
    for (i = 1; i <= SKY_BLUES; i++)
    {
        s16 c = sky_base[i];
        s16 r = (c >> 1) & 7;
        s16 g = (c >> 5) & 7;
        s16 b = (c >> 9) & 7;

        r += ((NAVY_R - r) * k) >> 8;
        g += ((NAVY_G - g) * k) >> 8;
        b += ((NAVY_B - b) * k) >> 8;

        pal[i] = (u16)((r << 1) | (g << 5) | (b << 9));
    }
    PAL_setColors(0, pal, 16, DMA);
}

static void hud_update(void)
{
    char num[8];
    s32 alt = ALT_MIN_FT + (s32)FROM_FIX(alt_fix) * FT_PER_PX;
    s32 kt = KT_CRUISE + (throttle * KT_PER_FIX >> FIX_SHIFT);

    // Fixed widths, so the old value is always fully overwritten.
    intToStr(alt, num, 5);
    VDP_drawText(num, 5, 1);
    intToStr(kt, num, 3);
    VDP_drawText(num, 5, 2);
}

static void flying_init(void)
{
    PAL_setPalette(PAL0, sky_img.palette->data, DMA);
    PAL_setPalette(PAL1, plane_spr.palette->data, DMA);

    // The sky is exactly one scroll plane (512x256), so it wraps cleanly.
    VDP_drawImageEx(BG_B, &sky_img, TILE_ATTR_FULL(PAL0, FALSE, FALSE, FALSE,
                    TILE_USER_INDEX), 0, 0, FALSE, TRUE);

    // Sonic needs no line of his own: he and the Tornado are both drawn from
    // Sonic 2's shared character palette, so PAL1 already holds his colours.

    u16 i;

    memcpy(sky_base, sky_img.palette->data, sizeof(sky_base));

    plane_x = TO_FIX(72);
    vel_x = throttle = vs = 0;
    alt_fix = TO_FIX(ALT_PX_MAX / 2);   // start mid-band, room either way
    route_pos = 0;
    scroll_sky = scroll_gnd = 0;
    sky_tint();

    PAL_setPalette(PAL2, airliner_spr.palette->data, DMA);

    // Traffic sits behind the Tornado. Order of addition is NOT enough to get
    // that: on the Mega Drive the sprite that comes FIRST in the list draws in
    // front, so adding traffic first would put it on top. Depth is explicit -
    // larger is further back.
    for (i = 0; i < TRAFFIC_N; i++)
    {
        traffic[i].x = TO_FIX(SCR_W + 60 + i * 420);
        traffic[i].alt_px = westbound_levels[(i * 2) % 5];
        traffic[i].spr = SPR_addSprite(&airliner_spr, SCR_W, 0,
                                       TILE_ATTR(PAL2, FALSE, FALSE, TRUE));
        SPR_setDepth(traffic[i].spr, 200);
        // Let SGDK cull these itself. Forcing them visible submits the ones
        // waiting off-screen to the VDP, and the hardware only draws 320 pixels
        // of sprite per scanline in H40 - three 128px airliners plus the
        // Tornado exceeds that, and the overflow is dropped mid-sprite.
        SPR_setVisibility(traffic[i].spr, AUTO_FAST);
    }

    // The Sky Chase art already faces the way we fly, so no flip.
    plane = SPR_addSprite(&plane_spr, FROM_FIX(plane_x), PLANE_Y,
                          TILE_ATTR(PAL1, TRUE, FALSE, FALSE));
    SPR_setDepth(plane, 100);

    // Sonic rides the upper wing. He is added after the plane so he draws in
    // front of it, and he carries his own palette line: the shared character
    // palette, which is not the one the Tornado uses.
    sonic = SPR_addSprite(&sonic_spr,
                          FROM_FIX(plane_x) + SONIC_OFF_X,
                          PLANE_Y + SONIC_OFF_Y,
                          TILE_ATTR(PAL1, TRUE, FALSE, FALSE));
    SPR_setDepth(sonic, 50);            // in front of the plane he stands on

    hud_init();
    hud_update();

    // "only_air" from the free_vgms pack (CC0). SGDK compiles the VGM straight
    // to the XGM driver's format, so there is no conversion step of our own.
    XGM_setLoopNumber(-1);
    XGM_startPlay(only_air);
}

static void flying_update(void)
{
    u16 pad = JOY_readJoypad(JOY_1);

    if (pad & BUTTON_UP)    vs += VS_ACCEL;     // climb
    if (pad & BUTTON_DOWN)  vs -= VS_ACCEL;     // descend
    if (pad & BUTTON_LEFT)  { vel_x -= ACCEL_X; throttle -= ACCEL_X; }
    if (pad & BUTTON_RIGHT) { vel_x += ACCEL_X; throttle += ACCEL_X; }

    // Nothing held: ease back to level flight rather than stopping dead.
    if (!(pad & (BUTTON_UP | BUTTON_DOWN)))    approach_zero(&vs, VS_DRAG);
    if (!(pad & (BUTTON_LEFT | BUTTON_RIGHT))) {
        approach_zero(&vel_x, DRAG);
        approach_zero(&throttle, DRAG);
    }

    vs = clamp_fix(vs, -VS_MAX, VS_MAX);
    vel_x = clamp_fix(vel_x, -VEL_MAX_X, VEL_MAX_X);
    throttle = clamp_fix(throttle, -VEL_MAX_X, VEL_MAX_X);

    plane_x = clamp_fix(plane_x + vel_x, TO_FIX(MIN_X), TO_FIX(MAX_X));
    if (plane_x == TO_FIX(MIN_X) || plane_x == TO_FIX(MAX_X)) vel_x = 0;

    // The plane holds its altitude on screen; the sky moves instead. Climbing
    // means the world slides down past you, hence the negated scroll.
    alt_fix = clamp_fix(alt_fix + vs, 0, TO_FIX(ALT_PX_MAX));
    if (alt_fix == 0 || alt_fix == TO_FIX(ALT_PX_MAX)) vs = 0;
    VDP_setVerticalScroll(BG_B, -FROM_FIX(alt_fix));

    SPR_setPosition(plane, FROM_FIX(plane_x), PLANE_Y);
    SPR_setPosition(sonic, FROM_FIX(plane_x) + SONIC_OFF_X,
                           PLANE_Y + SONIC_OFF_Y);

    // Throttle, not screen velocity: pinned against the front of the box with
    // right still held is full power, not a standstill.
    {
        s16 speed = CRUISE_SPEED + FROM_FIX(throttle * 2);
        if (speed < 1) speed = 1;
        route_pos += speed;

        // Scrolling east means the world moves left, hence the negative offsets.
        scroll_sky -= speed;
        scroll_gnd -= speed / PARALLAX_DIV;
        VDP_setHorizontalScroll(BG_B, scroll_sky);
        VDP_setHorizontalScroll(BG_A, scroll_gnd);
    }

    // Traffic. Screen position comes from the difference between our altitude
    // and theirs, NOT from how far the sky has scrolled - the sky is scenery,
    // this is an instrument. So an airliner two levels above is genuinely off
    // the top of the screen until you climb toward it.
    {
        u16 i;
        s16 closing = CRUISE_SPEED + FROM_FIX(throttle * 2) + CLOSURE;
        s16 our_px = FROM_FIX(alt_fix);

        for (i = 0; i < TRAFFIC_N; i++)
        {
            s16 y;
            traffic[i].x -= TO_FIX(closing);

            if (FROM_FIX(traffic[i].x) < -AIRLINER_W)
            {
                // Gone past: bring it back from well ahead, far enough that two
                // airliners are never abreast on the same scanlines.
                traffic[i].x = TO_FIX(SCR_W + 200 + (random() & 511));
                spawn_seq++;
                // i*2 keeps the three slots on levels that stay distinct as the
                // sequence rotates, so no two are ever wingtip to wingtip.
                traffic[i].alt_px = westbound_levels[(i * 2 + spawn_seq) % 5];
            }

            // Off-screen vertically simply means positioned off-screen; SGDK's
            // own culling then keeps it out of the VDP's per-line budget.
            y = PLANE_Y + (our_px - traffic[i].alt_px);
            SPR_setPosition(traffic[i].spr, FROM_FIX(traffic[i].x), y);
        }
    }

    // The instruments only need to be readable, not smooth, and the sky tint
    // changes far too slowly to be worth a palette upload every frame.
    if ((route_pos & 7) == 0)
    {
        hud_update();
        sky_tint();
    }
}

int main(bool hardReset)
{
    (void)hardReset;

    VDP_setScreenWidth320();
    SPR_init();

    state = ST_FLYING;
    flying_init();

    while (TRUE)
    {
        switch (state)
        {
            case ST_FLYING: flying_update(); break;
            case ST_TITLE:  break;      // reserved
            case ST_PICKER: break;      // reserved
        }

        SPR_update();
        SYS_doVBlankProcess();
    }

    return 0;
}
