# CC:Tweaked Branch Miner

A `branch_miner.lua` interaktiv menubol allithato branch mining program.
Nem kell parancssori parametereket megadni: inditas utan kerdesenkent bekeri a
beallitasokat, osszefoglalja oket, majd a vegso ENTER-re indul el.

## Inditas

Masold a fajlt a turtle gepere `branch_miner` nevvel, majd futtasd:

```text
branch_miner
```

## Ladak elhelyezese

A turtle a kezdohelyen a banya fele nezzen. A ket lada mogotte legyen:

```text
Oldalnezet:

                    banya iranya ->
  [fuel lada]
  [leado lada] [TURTLE]
```

- A leado lada kozvetlenul a turtle mogott van.
- Az uzemanyaglada kozvetlenul a leado lada folott van.
- A turtle feletti blokk maradjon szabad, mert tankolaskor felmegy egyet.
- Az uzemanyagladaba csak egetheto targyat (peldaul szenet) tegyel.
- A biztonsagi tartalek legalabb 2, igy a turtle a felso ladat eleri.
- A legelso inditas elott legyen legalabb 2 fuel a turtle-ben vagy legyen
  egetheto targy a sajat inventoryjaban. Ez kell ahhoz, hogy fel tudjon menni
  a felso uzemanyagladahoz; kesobb a program mar nem engedi teljesen kifogyni.

## Mukodes

- Valaszthato 2 blokk magas alagut: a turtle elotti es feletti blokkot assa.
- Valaszthato 3 blokk magas alagut: az alatta, elotte es felette levo blokkot
  assa ki.
- Valaszthato 3x3-as alagut: a turtle minden szeletnel balra es jobbra is
  kiter, kiassa mindharom oszlop also es felso blokkjat, majd visszaall a
  kozepvonalra. A plusz oldaliranyu lepeseket a fuel-szamitas tartalmazza.
- A turtle relativ koordinatakat vezet. A pontos hazautigeny:
  `abs(x) + abs(y) + abs(z)`.
- Minden bovito lepes elott ellenorzi a hazaut uzemanyag-igenyet.
- Teljes inventory vagy keves uzemanyag eseten megjegyzi a munkapontot,
  hazater, urit, tankol, visszamegy ugyanoda, es folytatja.
- A munka vegen hazater, kiuriti az inventoryt, es az eredeti iranyba fordul.

## Az 1-es inventory slot

- Az 1-es slot kizarolag tankolasi slot.
- A turtle a kitermelt targyakhoz a 2-es slotot valasztja ki.
- Otthon az 1-es slot nem egetheto tartalmat lerakja a leado ladaba.
- Az uzemanyagladabol mindig az 1-es slotba vesz fel, es csak ebbol tankol.
- Az 1-es slotban maradt egetheto targyat felhasznalja vagy visszarakja az
  uzemanyagladaba.

## Folytatasi mod

A `Meglevo alagutban eloremegyek` modban add meg, hany blokk hosszu a mar
letezo fotengely. A turtle ezen a tavon eloremegy, majd onnan kezdi az uj
szakaszt. Az oldalagatok kiosztasanal ezt a tavolsagot is figyelembe veszi,
ezert az agak ritmusa folytatodik.

Fontos: a program nem hasznal GPS-t. Futas kozben ne mozgasd kezzel a turtle-t,
es ujrainditasnal mindig az eredeti kezdohelyre, az eredeti iranyban tedd le.

## Downloader: Pastebin vagy GitHub

A `downloader.lua` elejen a `DOWNLOAD_SOURCE` erteke valasztja ki a forrast:

```lua
local DOWNLOAD_SOURCE = "github" -- vagy: "pastebin"
```

A GitHub-beallitasok ugyanitt talalhatok. Publikus reponal a `token` maradjon
ures. Privat reponal egy `Contents: Read-only` jogosultsagu fine-grained token
adhato meg:

```lua
local GITHUB = {
    owner = "Forcas76",
    repo = "CCTurtle",
    branch = "main",
    token = "IDE_KERUL_A_TOKEN",
    tokenFile = ".github_token",
}
```

Biztonsagosabb megoldas, ha a token nem a programkodba, hanem a turtle
`.github_token` nevu fajljaba kerul egyetlen sorban. A fajlt a downloader nem
frissiti es nem irja felul. Igy a token nem tunik el a downloader sajat
frissitesekor, es veletlenul sem kerul bele a GitHub repoba. Ha ez a fajl
letezik, elsobbseget kap a kodban megadott `token` ertekevel szemben.

A fajlok forras- es celneve a `links` tablaban allithato. Jelenleg a repo
`branch_miner.lua` fajlja a turtle `main` programjakent telepul.

```text
downloader                 # minden komponens
downloader main            # csak a banyaszprogram
downloader downloader      # csak a downloader
```

A letoltes eloszor ideiglenes fajlba tortenik. A mar mukodo program csak
sikeres letoltes utan cserelodik le.
