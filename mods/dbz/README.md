# Dragon Ball Z: Buyuu Retsuden / L'Appel du Destin

Mods for the Mega Drive game. The disassembly lives in its own repo,
`dbzbr-disasm`, and is used here as a submodule.

## Where the line is

* **`dbzbr-disasm`** answers *what is the game*: the tracer and analysis tools,
  the ROM map, the text codec, and `tools/facts.py`, which states every address
  and layout once. Nothing in it writes bytes.
* **A mod here** answers *what do we change*. It imports the facts and emits a
  patched ROM.

If you learn something true of an unmodified ROM, it belongs in the disassembly,
even if only one mod needs it today. If you write a byte, it belongs in a mod.

## Mods

| dir | what |
|---|---|
| `dbz-colour-picker` | press B on the character select to fight in the second colour set. Confirmed on hardware. |
| `dbz-roster` | dump the fighter roster to JSON, edit it, build a ROM. Builds up to 64 fighters. Never run on hardware. |

## Running them

Both find the disassembly automatically when it sits next to this directory or
in the same workspace. Otherwise point them at it:

```bash
export DBZ_DISASM=/path/to/dbzbr-disasm
python3 dbz-colour-picker/patch.py "<rom>" out.md --button B
```

Each mod writes its builds to its own `rom/`, never a shared one, so a ROM is
always next to the code and data that produced it. None are committed. The disassembly repo holds only the stock game and analysis of it;
nothing we build lands there.
