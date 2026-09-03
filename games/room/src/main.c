#include <genesis.h>
#include "room.h"
#include "roomcol.h"

// CPC ROOM -- walk the room (controller 1), collide with walls/table/car/NPC.
// The NPC has a dialog bubble that renders text streamed from the Pico over the
// data channel (controller PORT 2), same protocol as the datalink ROM.

#define OP_PRINT   0x01
#define CTRL_START 0x1
#define CTRL_END   0x2

// speech bubble (tile coords) above the NPC
#define BUB_X0 6
#define BUB_Y0 2
#define BUB_X1 19
#define BUB_Y1 4
#define BUB_TXT_X (BUB_X0 + 1)
#define BUB_TXT_Y (BUB_Y0 + 1)
#define BUB_W     (BUB_X1 - BUB_X0 - 1)

static u8 box_blocked(s16 px, s16 py)
{
    if (px < 0 || py < 0 || px > 320 - 16 || py > 224 - 16) return TRUE;
    u16 c0 = px / 16, c1 = (px + 15) / 16, r0 = py / 16, r1 = (py + 15) / 16;
    return solid[r0][c0] || solid[r0][c1] || solid[r1][c0] || solid[r1][c1];
}

static void bubble_frame(void)
{
    u16 x, y;
    for (x = BUB_X0; x <= BUB_X1; x++) { VDP_drawText("-", x, BUB_Y0); VDP_drawText("-", x, BUB_Y1); }
    for (y = BUB_Y0; y <= BUB_Y1; y++) { VDP_drawText("|", BUB_X0, y); VDP_drawText("|", BUB_X1, y); }
    VDP_drawText("+", BUB_X0, BUB_Y0); VDP_drawText("+", BUB_X1, BUB_Y0);
    VDP_drawText("+", BUB_X0, BUB_Y1); VDP_drawText("+", BUB_X1, BUB_Y1);
    VDP_drawText("v", NPC_TX, BUB_Y1 + 1);          // tail pointing at the NPC
    VDP_drawText("...", BUB_TXT_X, BUB_TXT_Y);
}

static char bub[BUB_W + 1];
static u16  blen = 0, bshown = 0;

static void bub_reset(void)
{
    VDP_clearText(BUB_TXT_X, BUB_TXT_Y, bshown);
    blen = 0; bshown = 0; bub[0] = 0;
}
static void bub_char(char c)
{
    if (blen < BUB_W) { bub[blen++] = c; bub[blen] = 0; VDP_drawText(bub, BUB_TXT_X, BUB_TXT_Y); bshown = blen; }
}

int main(bool hardReset)
{
    VDP_init();
    JOY_setSupport(PORT_1, JOY_SUPPORT_3BTN);   // player pad
    JOY_setSupport(PORT_2, JOY_SUPPORT_OFF);    // data channel (raw)

    volatile u8 *data2 = (u8*)0xA10005;
    volatile u8 *ctrl2 = (u8*)0xA1000B;
    *ctrl2 = 0x00;

    VDP_drawImageEx(BG_B, &room_img,
                    TILE_ATTR_FULL(PAL0, FALSE, FALSE, FALSE, TILE_USER_INDEX),
                    0, 0, TRUE, TRUE);

    SPR_init();
    PAL_setPalette(PAL1, hero_spr.palette->data, CPU);
    PAL_setPalette(PAL2, npc_spr.palette->data, CPU);
    PAL_setPalette(PAL3, car_spr.palette->data, CPU);

    SPR_addSprite(&car_spr, CAR_TX * 16, CAR_TY * 16, TILE_ATTR(PAL3, FALSE, FALSE, FALSE));
    SPR_addSprite(&npc_spr, NPC_TX * 16, NPC_TY * 16, TILE_ATTR(PAL2, FALSE, FALSE, FALSE));

    s16 hx = 48, hy = 96;
    Sprite *hero = SPR_addSprite(&hero_spr, hx, hy, TILE_ATTR(PAL1, FALSE, FALSE, FALSE));

    bubble_frame();

    u8 last_clk = 0xFF, started = 0, have_hi = 0, hi = 0, got_op = 0, opcode = 0;

    while (TRUE)
    {
        // movement + collision
        u16 j = JOY_readJoypad(JOY_1);
        s16 dx = 0, dy = 0;
        if (j & BUTTON_LEFT)  dx = -2; else if (j & BUTTON_RIGHT) dx = 2;
        if (j & BUTTON_UP)    dy = -2; else if (j & BUTTON_DOWN)  dy = 2;
        if (dx && !box_blocked(hx + dx, hy)) hx += dx;
        if (dy && !box_blocked(hx, hy + dy)) hy += dy;
        SPR_setPosition(hero, hx, hy);

        // data channel -> NPC bubble
        u8 v = *data2, clk = (v >> 5) & 1, ctrl = (v >> 4) & 1, nib = v & 0x0F;
        if (clk != last_clk)
        {
            last_clk = clk;
            if (ctrl)
            {
                if (nib == CTRL_START) { started = 1; have_hi = 0; got_op = 0; bub_reset(); }
                else if (nib == CTRL_END) started = 0;
            }
            else if (started)
            {
                if (!have_hi) { hi = nib; have_hi = 1; }
                else
                {
                    u8 b = (hi << 4) | nib; have_hi = 0;
                    if (!got_op) { opcode = b; got_op = 1; }
                    else if (opcode == OP_PRINT) bub_char((char)b);
                }
            }
        }

        SPR_update();
        SYS_doVBlankProcess();
    }
    return 0;
}
