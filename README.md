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

## Menümagyarázó

Az első oszlopban pontosan az a rövid, ékezet nélküli felirat szerepel,
amely a turtle kijelzőjén látható. Mellette található az ékezetes cím és a
választás jelentése.

### Főmenü

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Branch 1x2` | Branch mining – 1×2 | Egy blokk széles, két blokk magas főutat és oldalágakat ás. |
| `Branch 1x3` | Branch mining – 1×3 | Egy blokk széles, három blokk magas főutat és oldalágakat ás. |
| `Egyenes 3x3` | Egyenes 3×3-as alagút | Oldalágak nélküli, három blokk széles és magas alagutat készít. Induláskor egy blokkal feljebb megy, így a kezdőszint lesz az alagút alja. |
| `Terulet asas` | Területásás | Elindítja a kísérleti területásó programot, ahol egy teljes téglatest méretei adhatók meg. |
| `Auto folytatas` | Automatikus folytatás | Betölti a mentett munkát, visszamegy a mentett pontra, majd onnan folytatja. |
| `Auto (nincs mentes)` | Automatikus folytatás (nincs mentés) | Jelenleg nincs használható mentés, ezért az automatikus folytatás nem választható. |

### Branch mining és 3×3-as alagút beállításai

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Uj munka` | Új munka | Új bányászást indít a kezdőponttól. |
| `Kezi folytatas` | Kézi folytatás | A turtle előbb végigmegy a már meglévő alagúton a megadott kezdő távolságig, majd ott kezdi az új szakaszt. Vésztartalék arra az esetre, ha nincs megfelelő mentés. |
| `Kezdo tavolsag` | Kezdő távolság | A már elkészült főút hossza, amelyen a turtle ásás nélkül előremegy. |
| `Alagut hossza` | Alagút hossza | Az egyenes 3×3-as alagút teljes hossza. |
| `Fotengely` | Főtengely hossza | A branch mining során elkészítendő új főút hossza. |
| `Oldalagat` | Oldalág hossza | Egy bal vagy jobb oldali bányaág hossza. |
| `Agak tavolsaga` | Ágak távolsága | Ennyi blokk marad két egymást követő oldalág között. Alapértéke 3. |
| `Fuel tartalek` | Üzemanyag-tartalék | Ennyi extra üzemanyagot tartson meg a program a kezdőpontra való visszaút kiszámított igényén felül. |
| `KISERLETI inv.` | KÍSÉRLETI inventory-kezelés | Bekapcsolja a következő drop tényleges helyigényét vizsgáló, kapacitásalapú lepakolási rendszert. Alapértelmezetten kikapcsolt. |

### Kísérleti automatikus fáklyázás

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `KISERLETI faklyazas` | KÍSÉRLETI fáklyázás | Beállítja, hogy a turtle használjon-e automatikusan fáklyákat. Bekapcsolva a 2-es inventory slot a fáklyáké. |
| `Kikapcsolva` | Kikapcsolva | Nem használ fáklyát, és nem keresi a fáklyás ládát. |
| `Bekapcsolva` | Bekapcsolva | Engedélyezi a fáklyázást; ha elfogy a fáklya, a turtle visszatér és újratölti a 2-es slotot. |
| `Fout: hany beasas` | Főút: hány beásásonként | Megadja, hogy a főúton hány elkészült oldalág után legyen fáklya. A főúti fáklyákat a kész útvonalon, a végső visszatéréskor rakja le. |
| `Ag: hany blokkonkent` | Ág: hány blokkonként | Az oldalág fáklyái közötti távolság. A turtle előbb kiássa az egész ágat, majd visszafelé rakja le a fáklyákat. |
| `Faklya tavolsag` | Fáklyák távolsága | Területásásnál a fáklyák közötti beállított távolság. |
| `Faklya helye (KISERLETI)` | Fáklya helye (KÍSÉRLETI) | Kiválasztja a fáklya lerakási módját. |
| `Oldalt: blokk ki, faklya be` | Oldalt: blokk ki, fáklya be | A turtle oldalra fordul, kiüt egy blokkot, majd a kialakított helyre próbálja tenni a fáklyát. |
| `A turtle feje fole` | A turtle feje fölé | A turtle felfelé próbálja elhelyezni a fáklyát. Ez a lerakási mód kísérleti. |

### Területásás beállításai

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Uj terulet` | Új terület | Új, téglatest alakú terület kiását állítja be. |
| `Auto folytatas` | Automatikus folytatás | Betölti a területásó mentését, visszamegy a mentett pontra, majd folytatja a munkát. |
| `Auto (nincs mentes)` | Automatikus folytatás (nincs mentés) | Nincs használható területásó-mentés. |
| `Szelesseg` | Szélesség | A turtle nézőpontjából a kiásandó terület oldalirányú mérete. |
| `Melyseg` | Mélység | A turtle előtti irányban mért hossz. |
| `Magassag` | Magasság | A kiásandó terület függőleges mérete. |
| `Fuel tartalek` | Üzemanyag-tartalék | A kiszámított visszaúthoz szükséges mennyiségen felül megtartandó extra üzemanyag. |
| `KISERLETI inv.` | KÍSÉRLETI inventory-kezelés | A területásásnál is bekapcsolja a kapacitásalapú ellenőrzést és az `inventory_state.txt` frissítését. |

### Futás közbeni vezérlés

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Q/Ctrl+T: leallitas` | Q/Ctrl+T: leállítás | Biztonságos leállítást kér. A turtle elmenti az állapotát, visszatér a kezdőpontra, lepakol és feltankol. |
| `S: allapot` | S: állapot | Kiírja az aktuális munkafázist, pozíciót, irányt, üzemanyagszintet és a visszaúthoz szükséges mennyiséget. |

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

## KISERLETI: kapacitasalapu inventory-kezeles

Uj munka beallitasakor a `KISERLETI inv.` opcio kulon be- vagy kikapcsolhato.
Alapertelmezetten ki van kapcsolva. Kikapcsolva a korabbi inventory-ellenorzes
mukodik; bekapcsolva az `inventory_manager.lua` modul vizsgalja meg minden
blokk kiutese elott, hogy a varhato drop tenylegesen elfer-e.

Az uj rendszer nem csak azt nezi, hogy van-e valamelyik stackben szabad hely.
Ismert dropnal megfelelo, reszben toltott stacket vagy ures banyaszslotot keres.
Nincs allandoan fenntartott biztonsagi puffer: uj blokkfajta szamara egyetlen
ures slot eleg. A turtle csak akkor ter haza, amikor a mar detektalt blokk
varhato dropja sem megfelelo stackbe, sem ures banyaszslotba nem fer be. Ilyenkor
meg a blokk kiutese elott lepakol, majd ugyanoda es ugyanabba az iranyba megy
vissza.

A modul az `inventory_state.txt` egyetlen JSON-soraban tarolja az inventory
pillanatkepet, a mar latott blokkokat es a futas kozben megtanult blokk-drop
kapcsolatokat. Programinditaskor, automatikus folytataskor es minden ladaktol
torteno elindulas elott a turtle valodi inventory-ja felulirja ezt a fajlt.
Ezert a TXT csak folytatasi segedadat; soha nem elozheti meg a slotok valos
tartalmat.

Az `S` allapotkijelzes bekapcsolt kiserleti modban az ures banyaszslotok szamat
is kiirja. A funkcio a branch mining, az egyenes
3x3-as alagut es a teruletasas minden elore, felfele es lefele vegzett
banyaszmuveletet ellenorzi. A fenti mukodes tesztfunkcio; rovid munkaval erdemes
kiprobalni, mielott kotelezo alapmechanikava valik.

## KÍSÉRLETI: ércdetektálás

Az ércdetektálás csak a `Branch 1x2` és `Branch 1x3` módoknál kapcsolható be.
Egy főági beásásnál először mindkét oldalág elkészül, ezután a turtle külön
végigvizsgálja a padlót, mennyezetet, oldalfalakat és az ág végét. Csak az
érclistában kijelölt blokkazonosítókat bányássza ki. A kapcsolódó érctelepet a
beállított mélység- és blokklimitig követi, majd az eltárolt útvonalon ugyanarra
az ágpontjára tér vissza. Az oldalági fáklyák csak az ércvizsgálat után kerülnek
a helyükre.

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `KISERLETI erckereses` | KÍSÉRLETI érckeresés | Be- vagy kikapcsolja az oldalágak utólagos ércvizsgálatát. |
| `Keresett ercek` | Keresett ércek | A kibányászandó blokkazonosítók mentett listája. |
| `A:+ uj` | Új blokk hozzáadása | `namespace:block_name` alakú vanilla vagy modolt blokkazonosítót vesz fel. |
| `D:- torles` | Saját blokk törlése | A kijelölt, kézzel felvett azonosítót törli. |
| `K: kesz` | Kész | Elmenti az `ore_targets.txt` fájlt és visszatér a beállításokhoz. |
| `Max melyseg` | Maximális mélység | Egy érctelepen belül engedélyezett követési mélység. Alapértéke 4. |
| `Max erc/telep` | Maximális érc/telep | Egyetlen kitérő alatt kibányászható ércek felső korlátja. Alapértéke 16. |

Advanced Turtle esetén a lista sorai és alsó gombjai kattinthatók. Normál
turtle esetén a nyílbillentyűk, Enter vagy Space, továbbá az `A`, `D` és `K`
billentyűk használhatók. A vanilla ércek csoportosan jelölhetők; például a
gyémánt kiválasztása a normál és a deepslate változatot is bekapcsolja. Modolt
ércek kézzel vehetők fel.

Az ércjárás külön útvonalvermet vezet. Inventoryürítés vagy tankolás előtt a
turtle ezen hátrál ki a főági csomópontig, onnan megy a ládákhoz, majd ugyanazt
az utat játssza vissza. A `Q`/`Ctrl+T` leállítás és az automatikus folytatás is
ezt a mentett útvonalat használja. Az állapot a `branch_miner_state.txt`, az
érclista az `ore_targets.txt` egyetlen felülírt sorában található.

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
beallitasakor a faklyazas opcionalisan bekapcsolhato. Branch miningnal a
foutvonal beasasainak gyakorisaga es az oldalagi blokk-tavolsag kulon adhato
meg. Minden oldalagat sajat tavolsagszamlalast kezd. Az agat eloszor teljesen
kiassa, feljegyzi a kijelolt pontokat, majd visszafele rakja le a faklyakat.
A foutvonalon is eloszor befejezi a teljes kijelolt szakaszt es az oldalagat,
majd a vegso hazauton helyezi el a kiszamitott faklyakat. Ha egy fej folotti
faklya elagazasi pontra esne, a kovetkezo ep oldalfalu pontig halasztja.

Ket lerakasi mod valaszthato:

- `Oldalt`: elfordul, kiut egy oldalso blokkot, majd a helyere teszi a faklyat.
- `Fej folott`: a kiserleti `placeUp` muvelettel a turtle feletti szabad
  mezobe probalja rakni. Eloszor a jobb, majd a bal oldalfal fele fordul, hogy
  ne a kovetkezo kibontando blokkhoz tapadjon, utana visszaall az eredeti
  iranyba. A jatek donti el, talal-e megfelelo tapadasi feluletet.

Teruletkitoresnel az oldalso mod csak a kijelolt terulet kulso peremen rak.
A fej folotti mod a megadott cellatavolsagot hasznalja, ezert a kitermelt
terfogaton belul is maradhat faklya.

Ha a 2-es slot kiurul, a turtle hazater. A fuel lada folotti faklyas ladabol
legfeljebb egy stacket vesz fel, majd visszamegy a mentett munkapontra. Ez a
funkcio kiserleti: eloszor rovid alaguttal vagy kis terulettel probald ki,
mert egyes modolt faklyak elhelyezesi szabalyai elterhetnek.

## Inditasi naplo

Az `action_log.lua` modul az `action_log.txt` fajlba minden programinditasnal
egyetlen sort fuz. A sor az idopontot, az elinditott banyaszati modot es az
indulaskori fuel-szintet tartalmazza. Mozgast, fordulast, koordinatat vagy mas
reszletes esemenyt nem naploz.

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
downloader actionlog       # csak az inditasi naplo modul
downloader inventory       # csak a kiserleti inventory modul
downloader ore             # csak a kiserleti ercdetektalo modul
downloader downloader      # csak a downloader
```

A letoltes eloszor ideiglenes fajlba tortenik. A mar mukodo program csak
sikeres letoltes utan cserelodik le.
