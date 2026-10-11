# CC:Tweaked Branch Miner

A `branch_miner.lua` interaktiv menubol allithato banyaszprogram.
Nem kell parancssori parametereket megadni: inditas utan kerdesenkent bekeri a
beallitasokat, osszefoglalja oket, majd a vegso ENTER-re indul el.
Minden szambeviteli mezonel az ures ENTER az alapertelmezett erteket valasztja.
Az oldalagatok alapertelmezett tavolsaga 3 blokk.

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
  [faklya lada]  (csak bekapcsolt faklyazasnal)
  [fuel lada]
  [leado lada] [TURTLE]
```

- A leado lada kozvetlenul a turtle mogott van.
- Az uzemanyaglada kozvetlenul a leado lada folott van.
- A turtle feletti blokk maradjon szabad, mert tankolaskor felmegy egyet.
- Az uzemanyagladaba csak egetheto targyat (peldaul szenet) tegyel.
- Kiserleti faklyazasnal a faklyas lada a fuel lada folott van, es csak
  faklyat tartalmazzon. A turtle feletti ket blokk maradjon szabad.
- A biztonsagi tartalek legalabb 2, igy a turtle a felso ladat eleri.
- A legelso inditas elott legyen legalabb 2 fuel a turtle-ben vagy legyen
  egetheto targy a sajat inventoryjaban. Ez kell ahhoz, hogy fel tudjon menni
  a felso uzemanyagladahoz; kesobb a program mar nem engedi teljesen kifogyni.
- Bekapcsolt faklyazasnal a harom lada bejarasahoz legalabb 4 kezdo fuel kell.

## Mukodes

- A `Branch 1x2` es `Branch 1x3` modnal fotengelyt, oldalaghosszt es agak
  kozotti tavolsagot lehet megadni.
- Az `Egyenes 3x3` mod eloszor valaszthato ki, es csak az alagut hosszat keri;
  ebben a modban nincsenek oldalagatok.
- A 3x3-as alagutnal a turtle minden szeletnel balra es jobbra is
  kiter, kiassa mindharom oszlop also es felso blokkjat, majd visszaall a
  kozepvonalra es az eredeti iranyba. A plusz oldaliranyu lepeseket a
  fuel-szamitas tartalmazza.
- A 3x3-as mod indulasakor a turtle egy blokkot felmegy. Igy az eredeti
  indulasi szint lesz az alagut also sora, a turtle pedig a kozepso sorban
  halad. Hazafele is a kozepso soron jon, es csak a kezdohelyen ereszkedik le.
- A turtle relativ koordinatakat vezet. A pontos hazautigeny:
  `abs(x) + abs(y) + abs(z)`.
- Minden bovito lepes elott ellenorzi a hazaut uzemanyag-igenyet.
- Teljes inventory vagy keves uzemanyag eseten megjegyzi a munkapontot,
  hazater, urit, tankol, visszamegy ugyanoda, es folytatja.
- A munka vegen hazater, kiuriti az inventoryt, es az eredeti iranyba fordul.

## Fenntartott inventory slotok

- Az 1-es slot kizarolag tankolasi slot.
- Faklyazas nelkul a turtle a kitermelt targyakhoz a 2-es slotot hasznalja.
- Bekapcsolt kiserleti faklyazasnal a 2-es slot a faklyake, a kitermelt
  targyak pedig a 3-as slottol kezdodnek.
- Otthon az 1-es slot nem egetheto tartalmat lerakja a leado ladaba.
- Az uzemanyagladabol mindig az 1-es slotba vesz fel, es csak ebbol tankol.
- Az uzemanyagladabol felvett teljes stacket betankolja. Ha 64 szenet vesz
  fel, mind a 64 darabot felhasznalja, nem csak a pillanatnyi uthoz elegendot.

## Automatikus folytatas

A program a `branch_miner_state.txt` fajl egyetlen soraba menti az aktualis
koordinatat, iranyt, beallitasokat, elvegzett fotengelyhosszt es az eppen vegzett
muveletet. Minden sikeres mozgas vagy fordulas utan ugyanazt a sort irja felul.

Ujrainditas utan az `Auto folytatas` mod betolti ezt az allapotot. Feltetelezi,
hogy a turtle-t a leallas ota nem mozgattak el es nem forgattak el. Eloszor
visszater a kezdohelyre, urit es tankol, majd visszamegy az utolso mentett
fotengely-ellenorzoponthoz. Ha egy oldalagat felbeszakadt, biztonsagosan ujra
bejárja az adott pont oldalágait, majd folytatja a munkat.

A `Kezi folytatas` mod tovabbra is elerheto, ha a mentes hianyzik, serult, vagy
a turtle-t kezzel athelyeztek.

## Kezi leallitas futas kozben

A banyaszat alatt a program folyamatosan figyeli a billentyuzetet. A `Q` vagy
a `Ctrl+T` biztonsagos leallitast ker: a turtle befejezi az aktualis atomi
3x3-as vagasi lepest, megorzi a mentest, hazater, lepakol es tankol. A munka
kesobb az `Auto folytatas` menuponttal folytathato.

Az `S` billentyu futas kozben kiirja az aktualis muveletet, haladast,
koordinatat, fuel-szintet, hazatavolsagot es inventory-kihasznaltsagot.

## Tetszoleges terulet

A fomenu `Terulet asas` pontja a kulon `excavator.lua` programot inditja.
A meretek a turtle nezopontjabol ertendok:

- szelesseg: a turtle-tol jobbra;
- melyseg: a turtle elore nezesi iranyaba;
- magassag: felfele.

A turtle a kiemelendo teglatest bal-also-elso sarka elott alljon, es a melyseg
iranyaba nezzen. A program kigyozo utvonalon jarja be a teljes terfogatot.
Amikor van meg felette kijelolt reteg, az also reteg bejarasa kozben minden
cellanal felfele is as, igy egy menetben ket fuggoleges reteget dolgoz fel.
Paratlan magassagnal a legfelso, utolso reteget kulon jarja be. Megtelt
inventory vagy keves fuel eseten hazater, urit es tankol, majd visszamegy az
aktualis munkapontra. Ugyanazt a ketladas elrendezest hasznalja, mint a branch
miner.

Az `excavator.lua` az `excavator_state.txt` egyetlen soraba menti a fizikai
poziciot, iranyt, beallitasokat, a teljesen feldolgozott cellak szamat es az
aktualis muveletet. A `Q` vagy `Ctrl+T` biztonsagosan leallitja es hazakuldi;
az `S` allapotot ir ki. Ujrainditas utan az `Auto folytatas` hazater, urit,
tankol, majd a kovetkezo meg nem kesz cellatol folytatja. A turtle-t a
varatlan leallas utan nem szabad kezzel elmozditani vagy elforgatni.

## KISERLETI: automatikus faklyazas

A `torch_manager.lua` kulon tesztmodul. Uj branch mining vagy teruletkitores
beallitasakor a faklyazas opcionálisan bekapcsolhato, es megadhato a faklyak
kozotti tavolsag. A modul egy oldalso, utvonalon kivuli helyet as ki, majd oda
probalja lerakni a faklyat. Teruletkitoresnel csak a kijelolt terulet kulso
peremen helyez el faklyat, hogy ne keruljon a kesobbi utvonalba.

Ha a 2-es slot kiurul, a turtle hazater. A fuel lada folotti faklyas ladabol
legfeljebb egy stacket vesz fel, majd visszamegy a mentett munkapontra. Ez a
funkcio kiserleti: eloszor rovid alaguttal vagy kis terulettel probald ki,
mert egyes modolt faklyak elhelyezesi szabalyai elterhetnek.

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
downloader excavator       # csak a teruletkitore program
downloader torch           # csak a kiserleti faklyakezelo modul
downloader downloader      # csak a downloader
```

A letoltes eloszor ideiglenes fajlba tortenik. A mar mukodo program csak
sikeres letoltes utan cserelodik le.
