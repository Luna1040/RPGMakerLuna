from pathlib import Path
p=Path('tests/equipment_v6.gd');s=p.read_text(encoding='utf-8-sig').replace('check(game.character.equipment==saved.equipment and game.character.inventory==saved.inventory and game.character.pending_loot==saved.pending_loot,"gear, bag and pending loot roundtrip")','''for field in ["equipment","inventory","pending_loot"]:
\t\tfor index in range(saved[field].size()):
\t\t\tif saved[field][index]!=game.character[field][index]:
\t\t\t\tprint("ROUNDTRIP DIFF ",field," ",index," ",JSON.stringify(saved[field][index])," => ",JSON.stringify(game.character[field][index]))
\t\t\t\tbreak
\tcheck(game.character.equipment==saved.equipment and game.character.inventory==saved.inventory and game.character.pending_loot==saved.pending_loot,"gear, bag and pending loot roundtrip")''');p.write_text(s,encoding='utf-8')
