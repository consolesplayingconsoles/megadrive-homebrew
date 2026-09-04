#!/usr/bin/env python3
"""Recolours written into bank B, replacing the stock alternate colours.

Bank B is the set the game used only for mirror matches. It has no lore value,
so rather than adding a third bank and spending ROM on it, a recolour takes its
place: same memory, better content.

A recolour is a sparse override on the fighter's bank A palette, so anything
not listed (skin, hair, boots, the white sash) stays exactly as it was.
"""

# Goku, End of Z. The gi ramp goes teal. There is no blue undershirt in that
# outfit, but recolouring those indices as skin would need the shading redone,
# so they become a dark teal instead: as dark as the blue was, reading as
# shadow under the gi rather than as a separate garment.
# What each index actually paints, established by isolating groups of them on
# hardware and looking at the silhouette:
#   4, 5, 6    the gi, top and pants. The safe thing to change.
#   8, 11      boots, belt, undershirt and bracelets, all at once. Too light and
#              the boots look wrong, too dark and the shirt reads as black.
#   9          NOT the undershirt: it lights with skin and the chest. Leave it.
#   1, 15      skin and its highlight        2, 3, 14   more skin, and outlines
#   12, 13     the Super Saiyan hair         0, 7, 10   shading on arms and boots
# Ramps, not fixed indices. Each screen numbers the palette differently, so the
# patcher asks the ROM which indices are costume and stretches these ramps over
# however many it finds, dark to light.
EOZ_GOKU = {
    'fighter': 0,          # roster index
    'gi':   [(0, 55, 55), (0, 146, 146), (73, 182, 182)],
    # One step darker than the gi's own dark: the shirt reads as cloth in shadow
    # rather than as black, and the boots keep separation from the outline.
    'trim': [(0, 36, 36), (0, 109, 109)],
}

# Alternatives kept for the record. EOZ_GOKU ships the second one. These can be
# cycled in game with --tune if a future outfit needs the judgement made by eye.
EOZ_TRIM = [
    {'trim_mid': (0, 36, 36),   'trim_light': (0, 73, 73)},      # 1 nearly black
    {'trim_mid': (0, 73, 73),   'trim_light': (0, 109, 109)},    # 2 gi in shadow
    {'trim_mid': (0, 109, 109), 'trim_light': (0, 146, 146)},    # 3 closer to the top
    {'trim_mid': (0, 36, 73),   'trim_light': (0, 73, 109)},     # 4 cooler shadow
]

# A diagnostic, not an outfit: every index gets a colour you cannot confuse with
# another, so one screenshot says which index paints which part of the sprite.
# Cheaper than guessing an index, shipping it, and asking "did the boots change?"
INDEX_MAP = {
    'fighter': 0,
    'by_number': True,
    'colours': {
        0:  (255, 0, 0),        # red
        1:  (0, 255, 0),        # green
        2:  (0, 0, 255),        # blue
        3:  (255, 255, 0),      # yellow
        4:  (255, 0, 255),      # magenta
        5:  (0, 255, 255),      # cyan
        6:  (255, 255, 255),    # white
        7:  (255, 146, 0),      # orange
        8:  (146, 0, 255),      # purple
        9:  (146, 255, 0),      # lime
        10: (255, 146, 182),    # pink
        11: (0, 146, 146),      # teal
        12: (146, 73, 0),       # brown
        13: (146, 146, 146),    # grey
        14: (0, 0, 146),        # navy
        15: (0, 146, 0),        # dark green
    },
}

RECOLOURS = {'eoz': EOZ_GOKU, 'indexmap': INDEX_MAP}
TUNINGS = {'eoz': EOZ_TRIM}
