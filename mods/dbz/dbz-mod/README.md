# DBZ Buyuu Retsuden: translation fixes and a colour picker

A small patch for *Dragon Ball Z: L'Appel du Destin* (Mega Drive), built on top
of the existing English fan translation. It fixes a few things that translation
left behind, and adds a bonus the game was already almost capable of.

## What it changes

**Translation**

* `RECOOME`, `KRILLIN` and `FRIEZA` instead of `LIKUM`, `KURILIN` and `FREEZA`.
  The roster tables are rebuilt and repointed, so a longer name is no harder
  than a shorter one.
* The computer player's label on the character select. The French ROM stores
  `ORDINATEUR` there as text; the English patch blanked those glyphs instead of
  translating them, so the label read as garbage. It now says `COMPUTER`.

**Bonus: pick your colours**

Every fighter already had a second colour set, which the game only ever used
when both players chose the same character. Press **B** on the character select
and that player fights in it: portrait, VS screen and match all follow. Each
player toggles their own, on their own pad.

**Bonus: End of Z Goku**

Goku's second colour set is no longer the stock mirror-match red. It is his End
of Z outfit: teal gi, with the undershirt and boots a darker shade of the same
so they read as cloth in shadow rather than as black.

## Applying it

You need your own copy of the game. Nothing here contains a ROM.

1. Start from *Dragon Ball Z: L'Appel du Destin (France)*, sha1
   `5ff71986f4911b5dfd16598a5a3a9ba398c92c60`
2. Apply the English translation patch `byreng095a` (not included, and not ours)
3. Apply `rom/dbz-cpc-bonus.ips`

## Credits

The English translation is someone else's work and is not included here; this
patch simply sits on top of it. Several other patches for this game taught us
where things live, by reading what regions they touch: a colour hack and DONUS
for the palettes, a sprite replacement for the art, a voice hack for the sound
driver, and a new character select for the screen code. None of their work is
included either.

## Where this came from

It is a by-product of a disassembly project rather than the point of it. The
ROM was mapped from scratch: a recursive-descent 68000 tracer, the engine's
dispatch idioms, the text encoding solved from French and English saying the
same sentence, and the palette layout worked out by running probe ROMs on real
hardware. Everything found is written down in the disassembly repo, addresses
and all, so the next person does not have to rediscover it.

The tooling that produced this patch is in the same repo: a roster kit that
turns the fighter list into JSON and rebuilds the tables (verified to reproduce
the stock ROM byte for byte), a text codec, an IPS reader and writer, and the
patcher here.

**Collaborators welcome.** The interesting part is not this patch, it is that
the method generalises: find the engine's dispatch idiom, let other people's
patches tell you where the data is, and measure with probe ROMs rather than
infer. If that sounds useful for a game you care about, come and take the tools
apart with us.
