#include <genesis.h>

// CPC MEGA DRIVE data-link ROM. A top menu picks one of two apps, both over the port-2 link:
//
//   Music Player -- AUTONOMOUS: the MD asks the Pi for the track list, renders its own menu,
//                   reads P1, and on A tells the Pi to stream the track (played on the SN76489).
//   Debug        -- PASSIVE receiver: the old data-link view (live port bits, state, opcode,
//                   last byte, received text, graphics). The Pico drives; the MD just shows it.
//
// The link is HALF-DUPLEX on the 6 port-2 lines (bits0-3 nibble, bit4 CTRL, bit5 CLK), same
// START/opcode/payload/END framing both ways -- only the driver changes:
//   Pico -> MD : Pico drives, MD reads (DIR2=0x00). Opcodes OP_PRINT/OP_RENDER/OP_PSG/OP_LIST.
//   MD -> Pico : MD drives (DIR2=0x3F), self-clocked, Pico reads. Opcodes REQ_LIST/REQ_PLAY.
// Turn-taking is strict request->response. Idle lines float high (id=0xF), never a valid START.

#define CTRL_START 0x1
#define CTRL_END   0x2
// Pico -> MD
#define OP_PRINT   0x01
#define OP_RENDER  0x02
#define OP_PSG     0x03
#define OP_LIST    0x20   // payload = track names separated by '\n'
// MD -> Pico
#define REQ_LIST   0x10   // no payload
#define REQ_PLAY   0x11   // payload = 1 index byte

#define PSG_PORT ((volatile u8*)0xC00011)

static volatile u8 *DATA2 = (u8*)0xA10005;   // PORT 2 data
static volatile u8 *DIR2  = (u8*)0xA1000B;   // PORT 2 direction (0=in, 1=out per bit)

#define TXT_ROW 9
#define TXT_COL 7
#define GFX_ROW 12
#define GFX_COL 3

static void screen_clear(void) { VDP_clearTextArea(0, 0, 40, 28); }

// ══ shared: PSG streaming + frame receive (MD reads a Pico-driven frame) ═══════════════
// Tight loop, no VSync. Each rebuilt byte goes straight to the chip. Runs until END. Call
// with interrupts OFF so a vblank can't steal a fast edge.
static void psg_stream(u8 first_clk)
{
    u8 last_clk = first_clk, have_hi = 0, hi = 0;
    while (TRUE)
    {
        u8 v   = *DATA2;
        u8 clk = (v >> 5) & 1;
        if (clk != last_clk)
        {
            last_clk = clk;
            if ((v >> 4) & 1) { if ((v & 0x0F) == CTRL_END) return; }
            else
            {
                u8 nib = v & 0x0F;
                if (!have_hi) { hi = nib; have_hi = 1; }
                else { *PSG_PORT = (u8)((hi << 4) | nib); have_hi = 0; }
            }
        }
    }
}

// Read one Pico-driven frame. OP_PSG streams immediately (ints off); others buffer payload.
// Returns payload length; *out_op = opcode (0 = timed out with no reply).
// No-reply give-up. It only ever elapses with NO link (e.g. an emulator): a real reply's
// first edge resets it, so this just bounds the "loading" freeze. ~1s; tune if it feels off.
#define MD_TIMEOUT 500000UL

static u16 md_recv(u8 *buf, u16 maxlen, u8 *out_op)
{
    u32 timeout = MD_TIMEOUT;
    u8 started = 0, have_hi = 0, hi = 0, got_op = 0, opcode = 0;
    u16 n = 0;
    u8 last_clk = (u8)((*DATA2 >> 5) & 1);
    *out_op = 0;
    while (timeout--)
    {
        u8 v   = *DATA2;
        u8 clk = (u8)((v >> 5) & 1);
        if (clk == last_clk) continue;
        last_clk = clk;
        timeout = MD_TIMEOUT;                      // reset watchdog on any activity
        if ((v >> 4) & 1)
        {
            u8 id = v & 0x0F;
            if (id == CTRL_START) { started = 1; have_hi = 0; got_op = 0; n = 0; }
            else if (id == CTRL_END && started) { *out_op = opcode; return n; }
        }
        else if (started)
        {
            u8 nib = v & 0x0F;
            if (!have_hi) { hi = nib; have_hi = 1; }
            else
            {
                u8 b = (u8)((hi << 4) | nib); have_hi = 0;
                if (!got_op)
                {
                    opcode = b; got_op = 1;
                    if (opcode == OP_PSG)
                    {
                        SYS_disableInts();
                        psg_stream(last_clk);
                        SYS_enableInts();
                        *out_op = OP_PSG; return 0;
                    }
                }
                else if (n < maxlen) buf[n++] = b;
            }
        }
    }
    return 0;
}

// ══ send: MD drives a command frame to the Pico (self-clocked) ═════════════════════════
static u8 tx_clk = 1;

static void tx_xfer(u8 is_ctrl, u8 nib)
{
    volatile u16 d;
    u8 base = (u8)((nib & 0x0F) | (is_ctrl ? 0x10 : 0));
    *DATA2 = (u8)(base | (tx_clk ? 0x20 : 0));     // data first, clk unchanged
    for (d = 0; d < 60; d++) { }                   // settle
    tx_clk ^= 1;
    *DATA2 = (u8)(base | (tx_clk ? 0x20 : 0));     // toggle clk -> edge, data already stable
    for (d = 0; d < 1500; d++) { }                 // hold ~2ms so the Pico's poll catches it
}

static void tx_byte(u8 b) { tx_xfer(0, (u8)((b >> 4) & 0xF)); tx_xfer(0, (u8)(b & 0xF)); }

static void md_send(u8 opcode, const u8 *payload, u16 len)
{
    u16 i;
    *DATA2 = 0x3F;                 // preload idle-high, THEN drive -> no glitch edge
    *DIR2  = 0x3F;
    tx_clk = 1;
    tx_xfer(1, CTRL_START);
    tx_byte(opcode);
    for (i = 0; i < len; i++) tx_byte(payload[i]);
    tx_xfer(1, CTRL_END);
    *DATA2 = 0x3F;
    *DIR2  = 0x00;                 // release, back to input -- listen for the reply
}

// ══ MUSIC PLAYER ══════════════════════════════════════════════════════════════════════
#define MAXSONGS 16
#define NAMELEN  28
static char songs[MAXSONGS][NAMELEN];
static u8   nsongs = 0;

static void parse_list(const u8 *buf, u16 len)
{
    u16 i = 0; u8 c = 0;
    nsongs = 0;
    while (i < len && nsongs < MAXSONGS)
    {
        u8 ch = buf[i++];
        if (ch == '\n' || ch == 0) { songs[nsongs][c] = 0; if (c > 0) nsongs++; c = 0; }
        else if (c < NAMELEN - 1) songs[nsongs][c++] = (char)ch;
    }
    if (c > 0 && nsongs < MAXSONGS) { songs[nsongs][c] = 0; nsongs++; }
}

#define LIST_ROW 5
static void render_songs(u8 cursor)
{
    u8 i;
    VDP_clearTextArea(0, LIST_ROW, 40, MAXSONGS + 1);
    for (i = 0; i < nsongs; i++)
    {
        VDP_drawText((i == cursor) ? ">" : " ", 2, LIST_ROW + i);
        VDP_drawText(songs[i], 4, LIST_ROW + i);
    }
}

#define STATUS_ROW 3
static void status_msg(const char *s)
{
    VDP_clearText(0, STATUS_ROW, 40);      // wipe the whole row first -> no bleed-through
    VDP_drawText(s, 2, STATUS_ROW);
}

static void request_list(void)
{
    u8 op; static u8 buf[512]; u16 len;
    status_msg("Loading tracks...");
    md_send(REQ_LIST, 0, 0);
    len = md_recv(buf, sizeof(buf), &op);
    if (op == OP_LIST) { parse_list(buf, len); status_msg(""); }
    else status_msg("No link, START to retry");
}

static void music_player(void)
{
    u8 cursor = 0;
    u16 prev = JOY_readJoypad(JOY_1);
    screen_clear();
    VDP_drawText("MUSIC PLAYER", 2, 1);
    request_list();
    render_songs(cursor);
    while (TRUE)
    {
        u16 j, pressed;
        SYS_doVBlankProcess();
        j = JOY_readJoypad(JOY_1);
        pressed = (u16)(j & ~prev);
        prev = j;
        if (pressed & BUTTON_B) return;
        if ((pressed & BUTTON_UP)   && cursor > 0)          { cursor--; render_songs(cursor); }
        if ((pressed & BUTTON_DOWN) && cursor + 1 < nsongs) { cursor++; render_songs(cursor); }
        if (pressed & BUTTON_START) { cursor = 0; request_list(); render_songs(cursor); prev = JOY_readJoypad(JOY_1); }
        if ((pressed & BUTTON_A) && nsongs > 0)
        {
            u8 op2, idx = cursor; u8 tmp[8];
            status_msg("> playing");
            md_send(REQ_PLAY, &idx, 1);
            md_recv(tmp, sizeof(tmp), &op2);       // OP_PSG streams inside md_recv
            status_msg("");
            prev = JOY_readJoypad(JOY_1);          // swallow the held A
        }
    }
}

// ══ DEBUG (passive data-link view) ════════════════════════════════════════════════════
static void clear_gfx(void)
{
    u16 r;
    for (r = GFX_ROW; r < GFX_ROW + 8; r++) VDP_clearText(GFX_COL, r, 12);
}

static void draw_graphic(u8 id)
{
    clear_gfx();
    if (id == 0)
    {
        VDP_drawText(" #### ",  GFX_COL, GFX_ROW + 0);
        VDP_drawText("#    #",  GFX_COL, GFX_ROW + 1);
        VDP_drawText("# oo #",  GFX_COL, GFX_ROW + 2);
        VDP_drawText("#    #",  GFX_COL, GFX_ROW + 3);
        VDP_drawText("#\\__/#", GFX_COL, GFX_ROW + 4);
        VDP_drawText(" #### ",  GFX_COL, GFX_ROW + 5);
    }
    else if (id == 1)
    {
        VDP_drawText(" _  _ ", GFX_COL, GFX_ROW + 0);
        VDP_drawText("( \\/ )", GFX_COL, GFX_ROW + 1);
        VDP_drawText(" \\  / ", GFX_COL, GFX_ROW + 2);
        VDP_drawText("  \\/  ", GFX_COL, GFX_ROW + 3);
    }
    else { char b[4]; intToHex(id, b, 2); VDP_drawText("gfx?", GFX_COL, GFX_ROW); VDP_drawText(b, GFX_COL + 6, GFX_ROW); }
}

static void debug_view(void)
{
    char txt[41]; u16 tlen = 0, shown = 0;
    u8 last_clk = 0xFF, started = 0, have_hi = 0, hi = 0, got_op = 0, opcode = 0;
    char hexb[4];
    u16 prev = JOY_readJoypad(JOY_1);
    txt[0] = 0;

    screen_clear();
    VDP_drawText("CPC Genesis  -  Debug", 1, 1);
    VDP_drawText("bits 012345:", 1, 3);
    VDP_drawText("state:", 1, 5);
    VDP_drawText("op:", 1, 6);
    VDP_drawText("byte:", 1, 7);
    VDP_drawText("text:", 1, TXT_ROW);

    while (TRUE)
    {
        u16 i, j, pressed;
        u8 v, clk, ctrl, nib;
        SYS_doVBlankProcess();

        j = JOY_readJoypad(JOY_1);
        pressed = (u16)(j & ~prev);
        prev = j;
        if (pressed & BUTTON_B) return;

        v    = *DATA2;
        clk  = (u8)((v >> 5) & 1);
        ctrl = (u8)((v >> 4) & 1);
        nib  = (u8)(v & 0x0F);

        for (i = 0; i < 6; i++) VDP_drawText((v & (1 << i)) ? "1" : "0", 14 + i * 2, 3);

        if (clk != last_clk)
        {
            last_clk = clk;
            if (ctrl)
            {
                if (nib == CTRL_START)
                {
                    started = 1; have_hi = 0; got_op = 0; tlen = 0; txt[0] = 0;
                    VDP_clearText(TXT_COL, TXT_ROW, shown); shown = 0;
                    VDP_drawText("--        ", 7, 6);
                    VDP_drawText("START     ", 8, 5);
                }
                else if (nib == CTRL_END && started) { started = 0; VDP_drawText("END       ", 8, 5); }
            }
            else if (started)
            {
                if (!have_hi) { hi = nib; have_hi = 1; }
                else
                {
                    u8 b = (u8)((hi << 4) | nib); have_hi = 0;
                    intToHex(b, hexb, 2);
                    VDP_drawText(hexb, 7, 7);
                    VDP_drawText("DATA      ", 8, 5);
                    if (!got_op)
                    {
                        opcode = b; got_op = 1;
                        intToHex(b, hexb, 2); VDP_drawText(hexb, 7, 6);
                        if (opcode == OP_PSG)
                        {
                            VDP_drawText("PSG STREAM", 8, 5);
                            SYS_disableInts(); psg_stream(last_clk); SYS_enableInts();
                            started = 0; got_op = 0;
                        }
                    }
                    else if (opcode == OP_PRINT && tlen < 31)
                    {
                        txt[tlen++] = (char)b; txt[tlen] = 0;
                        VDP_drawText(txt, TXT_COL, TXT_ROW); shown = tlen;
                    }
                    else if (opcode == OP_RENDER) draw_graphic(b);
                }
            }
        }
    }
}

// ══ TOP MENU ══════════════════════════════════════════════════════════════════════════
static const char *APPS[2] = { "Music Player", "Debug" };

static u8 top_menu(void)
{
    u8 cursor = 0;
    u16 prev = JOY_readJoypad(JOY_1);
    screen_clear();
    VDP_drawText("CPC Genesis", 14, 4);
    while (TRUE)
    {
        u8 i; u16 j, pressed;
        for (i = 0; i < 2; i++)
        {
            VDP_drawText((i == cursor) ? ">" : " ", 14, 10 + i);
            VDP_drawText(APPS[i], 16, 10 + i);
        }
        SYS_doVBlankProcess();
        j = JOY_readJoypad(JOY_1);
        pressed = (u16)(j & ~prev);
        prev = j;
        if ((pressed & BUTTON_UP)   && cursor > 0) cursor--;
        if ((pressed & BUTTON_DOWN) && cursor < 1) cursor++;
        if (pressed & BUTTON_A) return cursor;
    }
}

int main(bool hardReset)
{
    VDP_init();
    JOY_setSupport(PORT_1, JOY_SUPPORT_3BTN);   // P1 drives every menu
    JOY_setSupport(PORT_2, JOY_SUPPORT_OFF);    // port 2 is our data link -- hands off
    *DIR2 = 0x00;                               // start as input

    while (TRUE)
    {
        u8 choice = top_menu();
        if (choice == 0) music_player();
        else             debug_view();
    }
    return 0;
}
