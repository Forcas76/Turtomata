# Turtomata — magyar dokumentáció

[English documentation](README.md)

## V2 kiserleti funkciok

A `main` menuben a feladatlapok szerkeszthetok: a nyilakkal/kattintassal
valassz mezot, majd az `Attekintes / inditas` utan az utolso Enter indit.
Esc/Backspace visszalep. A `Felbehagyott munka` a mentett beallitasokat,
haladast, fazist es fizikai poziciot kulon mutatja. A
`Munka kezelese` menuben az automatikus folytatas ki-be kapcsolhato;
a felszabaditas a mentest nem torli, de csak bazison allo turtle-n hasznald.
Ugyanitt a `Mentett munka torlese` opcioval a kivalasztott feladat
folytatasi allapota vegleg eltavolithato (a biztonsagi masolattal egyutt),
igy uj munka indithato. Ezt is csak bazison allo turtle-n hasznald;
feladatlanc torlesekor az aktiv reszfeladat mentese is torlodik.
A `Beallitasok > Navigacio es altalanos > Kozos bazis` adja az uj
koordinatas feladatok es lancok alapertelmezett vilag-X/Y/Z es facing
adatait. Meglevo feladatmentest ez a beallitas nem helyez at.

A farmnal a turtle a bazison indul, a leadolada mogotte, a fuel lada
a leadolada folott, a vetomag/takarmany lada a bazistól jobbra van.
Az 1-es slot fuel, a 2-es vetomag/takarmany. A novenyprofil csak ismert,
erett vanilla novenyt arat, majd ujraveti. Az allatetetes KISERLETI:
a ket sikeres `place` nem bizonyitja, hogy uj allat szuletett.
Ujrainditas utan a farm azonnal korbejar; a regi idozitore nem var.

A `Feladatlanc` egy mentett szerkesztheto sorrend: lepes hozzaadasa,
modositasa, masolasa, ki/bekapcsolasa, mozgatas fel/le es torles.
Az egyes lepesek
utan a turtle visszater a kozos bazisra; teruletasas es farm tavoli
koordinatan is indithato. Branch mining es utvonalkeszites lancban
jelenleg csak a bazisrol indithato, tavoli adapteruk meg nincs kesz.
A koordinatas farm utvonala akadalymentes, ismert jarohelyeket igenyel;
a jatekbeli probat a valodi farmon el kell vegezni.

Aktuális rendszerverzió: **v1.1.2**. A verzió központilag a `version.lua`
fájlban található, és megjelenik a turtle főmenüjében, a megfigyelő állapot- és
parancsoldalán, valamint a downloader telepítési menüjében.

A közös `localization.lua` magyar (`hu`) és angol (`en`) feliratokat tartalmaz.
Új telepítésnél az alapértelmezett nyelv angol; a korábban mentett magyar
nyelvbeállítás frissítés után is megmarad.
A turtle főmenüjében a `Beallitasok > Nyelv / Language` pontban váltható. A
megfigyelőn a bal/jobb nyíllal elérhető harmadik, `Beallitasok` oldalon állítható
ugyanez. A választás az adott eszköz `settings.txt` fájljába kerül, ezért
újraindítás után is megmarad. Az ismeretlen vagy dinamikus technikai üzenetek
biztonságos tartalékként az eredeti magyar szöveggel jelennek meg.

A turtle főmenü `Program frissitese` pontja a `downloader turtle`, a megfigyelő
parancsoldal `Megfigyelo frissitese` pontja pedig a `downloader monitor`
csomagot futtatja. Sikeres letöltés után az eszköz automatikusan újraindul, és
a hozzá tartozó `startup.lua` már a frissített programot tölti be.
Mindkét programfrissítés először magát a `downloader` programot tölti le.
Ezután az új downloader indul el, így az ugyanabban a frissítésben bevezetett
új komponenseket is látja; nincs szükség második frissítésre. Ha egy fájl
letöltése sikertelen, a program nem indítja újra az eszközt sikeresként.

Moduláris CC:Tweaked turtle-rendszer branch mininghoz, területásáshoz,
Nether-útépítéshez és kísérleti koordinátás navigációhoz.

Az indítandó központi program a `main` (`main.lua`). A feladatok beállítása,
folytatása és az általános beállítások kezelése innen történik. A
feladatmodulok közvetlen indítása átmenetileg továbbra is használható
vésztartalékként.

## Indítás

Az in-game turtle-ön vagy megfigyelő Computeren először töltsd le a telepítőt:

```text
pastebin get hnT1J5cK downloader
```

Utána indítsd a `downloader` programot, és válaszd ki a turtle vagy a
megfigyelő csomagját. A teljes csomag a publikus GitHub-repóból token nélkül
töltődik le; a downloaderben egyelőre a régi `Forcas76/CCTurtle` repoazonosító
marad, amíg a GitHub-repót is át nem nevezed.

```text
main
```

A menük nyílbillentyűkkel és Enterrel használhatók. Advanced Turtle esetén a
sorokra kattintani és görgetni is lehet. Backspace vagy Escape visszalép.
Számbevitelnél az üres Enter elfogadja a kijelzett alapértéket. A feladat csak
az összefoglaló után, a végső Enterre indul el.

## Menümagyarázó

Az első oszlopban a turtle képernyőjén látható, ékezet nélküli felirat áll.
A második oszlop az ékezetes cím, a harmadik pedig a működés rövid leírása.

### Főmenü

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Branch mining` | Branch mining | 1×2, 1×3 vagy egyenes 3×3-as bányajárat. |
| `Terulet kiasasa` | Terület kiásása | KÍSÉRLETI: megadott szélességű, mélységű és magasságú téglatest kitermelése. |
| `Utvonal keszites` | Útvonalkészítés | Lépcső, körbeépített védett vagy sima 1×2-es alagút, szükség esetén cobblestone padlóval. |
| `Koordinatara navigalas` | Koordinátára navigálás | KÍSÉRLETI: kézzel megadott világkoordinátáról célkoordinátára halad. |
| `Felbehagyott munka` | Félbehagyott munka | Aktív mentés kiválasztása és automatikus folytatása. |
| `Beallitasok` | Beállítások | Közös navigációs, biztonsági, inventory-, fáklya- és ércbeállítások. |
| `Diagnosztika` | Diagnosztika | Ellenőrzi a szükséges modulokat és kijelzi a fuel-szintet. |
| `Kilepes` | Kilépés | Bezárja a központi programot. |

### Branch mining

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Branch 1x2` | Branch mining – 1×2 | Egy blokk széles, két blokk magas főutat és oldalágakat ás. |
| `Branch 1x3` | Branch mining – 1×3 | Egy blokk széles, három blokk magas főutat és oldalágakat ás. |
| `Egyenes 3x3` | Egyenes 3×3-as alagút | Oldalág nélküli 3×3-as járat. Induláskor egyet felmegy, így a kezdőszint lesz az alagút alja. |
| `Uj munka` | Új munka | A kezdőponttól indít új munkát. |
| `Kezi folytatas` | Kézi folytatás | A már kész főúton a megadott távolságig előremegy, majd ott kezdi az új szakaszt. |
| `Kezdo tavolsag` | Kezdő távolság | A kézi folytatáskor bejárandó, már meglévő főút hossza. |
| `Fotengely` | Főtengely | Az új főút hossza. |
| `Oldalagat` | Oldalág | Egy bal vagy jobb oldali ág hossza. |
| `Agak tavolsaga` | Ágak távolsága | Két oldalág közötti távolság; alapértéke 3. |
| `Alagut hossza` | Alagút hossza | Az egyenes 3×3-as alagút hossza. |

Az 1×2 és 1×3 módnál opcionális a kísérleti érckeresés. A turtle előbb
elkészíti a bal és jobb ágat, majd végigjárja azokat, és a padlón, mennyezeten,
oldalfalakon, illetve az ág végén keresi a beállított érceket. A kapcsolódó
érctelepet a mélység- és blokklimitig követi, majd pontosan visszatér az ág
azon pontjára, ahonnan kitért.

Ha az oldalág normál kiásása közben közvetlenül előtte kijelölt ércet talál,
az érctelért azonnal megpróbálja végigkövetni. A művelet idejére megőrzi az
összes így kitermelt világpozíciót, külön a bal és jobb ághoz. Az utólagos
ágvizsgálat ezeken a már ismert járatcellákon nem fordul oldalra, nem járja
végig a magassági szinteket és nem ismétli meg az ellenőrzést. A telér olyan
oldalirányú koordinátái, amelyek nem részei az ág járóvonalának, nem okoznak
téves kihagyást. Az ideiglenes térkép a teljes bal–jobb ágművelet végén törlődik,
de megszakítás esetére addig az állapotmentés része.

### Területásás

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Szelesseg` | Szélesség | A turtle nézőpontjából jobbra mért méret. |
| `Melyseg` | Mélység | Az előre nézési irányban mért méret. |
| `Magassag` | Magasság | A kezdőszinttől felfelé mért méret. |

A turtle kígyózó útvonalon járja be a téglatestet. Ha van még felette
feldolgozandó réteg, felfelé is ás, így egy bejárással két réteget készíthet
el. A funkció kísérleti, ezért először kis területen érdemes kipróbálni.

### Útvonalkészítés

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Lepcso fel/le` | Lépcső fel/le | Blokkonként egy szintet emelkedő vagy süllyedő, két blokk fejterű lépcső. |
| `Vedett 1x2 alagut` | Védett 1×2-es alagút | Szabad térben padlót, oldalfalakat és mennyezetet épít a járat köré. |
| `Sima 1x2 alagut` | Sima 1×2-es alagút | Két blokk magas járatot ás. Ha nincs alatta blokk, cobblestone-nal pótolja a padlót. Sok víznél vagy lávánál tartósan fedett alagútra vált. |
| `Felfele` | Felfelé | Emelkedő lépcső. |
| `Lefele` | Lefelé | Süllyedő lépcső. |
| `Epitoanyag / Blokk` | Építőanyag / blokk | A használt blokk azonosítója, például `minecraft:cobblestone`. |

Fáklyázás nélkül a 2–5. slot építőanyag, a 6–16. slot bányászati tárhely.
Fáklyázással a 2. slot a fáklyáé, az építőanyag a 3–5. slotba kerül. Ha az
anyag elfogy, a turtle a mentett útvonalon hazamegy, a leadóládából feltölti,
majd visszatér.
Az új sima alagút módnál az építőanyag rögzítetten `minecraft:cobblestone`;
hiányzó padló esetén kér belőle a leadóládából. A fáklyázás opcionális.
Ha a fáklya nem helyezhető le, figyelmeztet és továbbhalad; az üres
fáklyaslot sem állítja le ezt a módot. A mentésfájl neve kompatibilitásból
továbbra is `nether_builder_state.txt`.

A sima 1×2-es mód az előtte, felette és alatta érzékelt folyadékot figyeli.
Öt lépésen belül három vizes lépésnél, illetve láva észlelésekor a hátralévő
szakaszt fedett 1×2-es profilban készíti: padló, kétoldalt falak és mennyezet.
A váltás a mentésbe kerül, újraindítás után is megmarad. A szükséges
cobblestone-t a leadóládából tölti fel. Ha a folyadékot nem tudja biztonságosan
lezárni, vagy elfogy az építőanyag, nem lép tovább vakon. A sima mód első,
váltás előtti vizes lépései még nem utólagosan burkoltak.

### KÍSÉRLETI koordinátás navigáció

A menü bekéri a turtle jelenlegi világkoordinátáját, a nézési irányát, a
célkoordinátát és opcionálisan a végső irányt. Az irányok:

- észak: `-Z`;
- kelet: `+X`;
- dél: `+Z`;
- nyugat: `-X`.

A koordinátát a program nem GPS-szel méri: a beírt kezdőadatokból számol.

### Élő Rednet-megfigyelés

A turtle program opcionálisan automatikusan megnyit minden csatlakoztatott
vezeték nélküli modemet. A hagyományos Wireless Modem és az Ender Modem is
támogatott. Ha nincs modem, a bányászati rendszer változatlanul működik.

A `remote_monitor.lua` ugyanazon a programon keresztül használható Pocket
Computeren és normál/Advanced Computeren. A nézet a terminál méretéhez igazodik,
és egyszerre több turtle-t, illetve ugyanazt a turtle-t több megfigyelőről is
lehet nézni.

Ha a megfigyelő Computerhez `monitor` periféria csatlakozik, a program
automatikusan az első megtalált külső monitorra is kirajzolja a teljes
felületet. A Computer saját terminálja közben aktív marad, tehát a két kijelző
egyszerre frissül, mindegyik a saját méretéhez igazodó elrendezéssel. Monitor
csatlakoztatását vagy eltávolítását futás közben is felismeri. Advanced
Monitoron érintéssel, a gépen pedig nyilakkal vagy egérrel választható turtle.

A megfigyelő saját terminálján a bal/jobb nyíl vált az `Állapot` és a
`Parancsok` oldal között. Külső monitor esetén a monitor mindig az élő
állapotoldalon marad, miközben a Computer terminálján használható a
parancsmenü. Pocket Computeren ugyanazon a kijelzőn történik az oldalváltás.
A parancsmenüben a fel/le nyíl vagy a kattintás választ, az Enter végrehajt.
A biztonságos leállítás és hazatérés kétszeri megerősítést kér. A turtle minden
parancsot elfogadási vagy hibaüzenettel igazol vissza.

A jelenlegi távoli parancsok:

- `Adatok frissitese`: azonnali teljes állapotcsomagot kér;
- `Lepakolas es folytatas`: a branch mining, területásás vagy Nether-építés
  biztonságos pontján visszatér a ládákhoz, lepakol, tankol és feltölti a
  szükséges készleteket, majd visszamegy a munkapontra és folytatja;
- `Munka leallitasa, haza`: befejezi az aktuális biztonságos műveletet,
  hazatér, és nem folytatja automatikusan a munkát.

A koordinátás navigációnak nincs ládakezelése, ezért annál a lepakolási
parancsot a turtle érthető hibaüzenettel elutasítja.

Nincs indításkori párosítás. A később bekapcsolt megfigyelő azonnal felderítési
üzenetet küld, a már dolgozó turtle pedig teljes állapotcsomaggal válaszol. Ezt
követően két másodpercenként érkezik heartbeat. Nyolc másodperc jelkimaradás
után a megfigyelő `OFFLINE` állapotot mutat, de tovább keresi az eszközt.

### Downloader telepítési menü

A `downloader` paraméter nélküli indításakor két csomag választható:

| Menüszöveg | Telepített rendszer |
|---|---|
| `Turtle program telepitese` | A teljes bányászati rendszer, Rednet-telemetria és egy `startup.lua`, amely bekapcsoláskor a `main` programot indítja. |
| `Megfigyelo telepitese` | A Rednet protokoll, a pocket/computer megfigyelő és egy `startup.lua`, amely bekapcsoláskor a `remote_monitor` programot indítja. |

Parancssorból ugyanez a `downloader turtle`, illetve `downloader monitor`
paranccsal indítható. A telepítés a már létező `startup.lua` fájlt lecseréli;
a downloader a sikeres csere idejére biztonsági másolatot használ.

A területásásnál külön bekapcsolható a `KISERLETI koordinatas indulas`.
Ilyenkor a ládabázis világkoordinátája és facingje változatlan marad, a program
pedig egy megadott munkapontra küldi a turtle-t. Az ásás kezdőiránya a
ládabázis kezdőirányához képest választható: egyenesen, jobbra, hátra vagy
balra. Ürítéshez, tankoláshoz és fáklyáért mindig az eredeti ládákhoz tér
vissza, majd ugyanarra a munkapontra és facingre áll vissza.

Érckeresés mellett az oldalági fáklyák az érckereső visszaútján kerülnek le.
Így nincs külön fáklyázó bejárás. Az élő állapotpanel az érckeresés lépései
alatt is frissíti a pozíciót, az eltelt időt és a hátralévő becslést.
Indítás után a turtle-t nem szabad kézzel elmozgatni vagy elforgatni. Nyílt
út módban akadálynál biztonságosan megáll és ment; ásó módban megpróbál utat
nyitni. Ismeretlen víz- vagy lávahelyzetnél nem választ vak kerülőutat.

### Beállítások

| A kijelzőn | Ékezetes cím | Magyarázat |
| --- | --- | --- |
| `Navigacio es altalanos` | Navigáció és általános | Kezdő műveletidő, koordinátás mód és fuel-tartalék. |
| `Biztonsag es helyzetkezeles` | Biztonság és helyzetkezelés | Víz/láva lezárása, ismétlési limit, tömítőblokk és fáklyahiba viselkedése. |
| `Inventory KISERLETI` | KÍSÉRLETI inventory-kezelés | A következő blokk dropjának tényleges elférését vizsgáló rendszer. |
| `Faklyazas` | Fáklyázás | Alapértelmezett engedélyezés, távolság és elhelyezési mód. |
| `Erckereses` | Érckeresés | Alapértelmezett engedélyezés, érclista és követési limitek. |
| `Alapertekek visszaallitasa` | Alapértékek visszaállítása | Újra létrehozza a közös alapbeállításokat. |

Az érclistában az új blokk teljes alakja `<mod_neve>:<blokk_neve>`, például
`minecraft:coal_ore`. A vanilla rövid forma (`coal_ore`) automatikusan
`minecraft:` előtagot kap. A listában az `A` hozzáad, a `D` töröl vagy
kikapcsol, a `K` ment és kilép; egérrel is kezelhető.

## Automatikus fáklyázás – KÍSÉRLETI

Bekapcsolva a 2. slot mindig a fáklyáé. A fáklyás láda a fuel-láda fölött
legyen. Ha a fáklya elfogy, a turtle hazatér és feltölti a slotot.

Branch miningnál külön állítható:

- a főúti gyakoriság: hány teljes beásás után legyen fáklya;
- az oldalági távolság: hány blokkonként legyen fáklya.

A főágon a turtle a kijelölt beásásnál, az esetleges oldalágak elkészülte
után azonnal próbál fáklyát rakni. Érckeresés nélküli mellékágon már az
adott blokk kiásása után próbálkozik; érckereséssel továbbra is az ág
átvizsgálását követő visszaúton fáklyáz. Az `Oldalt` mód falba
helyez, a `Fej folott` mód felfelé próbál fali fáklyát rögzíteni. Sikertelen
lerakásnál másik oldalt, fej fölötti helyet, majd szükség esetén támaszblokkot
próbál; branch miningnál a sikertelen lerakás figyelmeztetés, nem
feladatmegszakítás.

## Ládák és fenntartott slotok

A turtle a kezdőhelyen a munka irányába nézzen:

```text
Oldalnézet:

                    munka iránya ->
  [fáklyás láda]  (csak bekapcsolt fáklyázásnál)
  [fuel-láda]
  [leadóláda] [TURTLE]
```

- A leadóláda közvetlenül a turtle mögött van.
- A fuel-láda a leadóláda fölött van.
- A fáklyás láda bekapcsolt fáklyázásnál a fuel-láda fölött van.
- Az 1. slot kizárólag tankolási slot. Nem éghető tartalmát a turtle lerakja.
- A fuel-ládából felvett teljes stacket betankolja; 64 szén esetén mind a 64-et.
- A 2. slot bekapcsolt fáklyázásnál kizárólag fáklyaslot.
- A ládák eléréséhez a turtle fölötti helyet szabadon kell hagyni.

## Inventory-kezelés – KÍSÉRLETI

Bekapcsolva a program minden ládától való elinduláskor frissíti az
`inventory_state.txt` fájlt. Új blokk detektálásakor ellenőrzi, hogy annak
várható dropja elfér-e meglévő stackben vagy üres bányászslotban. Csak akkor
tér haza, ha a detektált item már ténylegesen nem fér be. A fájl egyetlen
felülírt JSON-sort tartalmaz; nem eseménynapló.

## Navigáció, mentés és helyreállítás

Minden feladat a közös `navigation.lua` modult használja. A modul tartja
nyilván a relatív pozíciót és irányt, számolja a hazautat, kezeli az egzakt
útvonalvermet, és minden mozgás előtt ment egy függő tranzakciót. Váratlan
újraindítás után ezt egyezteti a mentett pozícióval, így nem alkalmazza kétszer
ugyanazt a lépést.

Állapotfájlok:

- `branch_miner_state.txt`;
- `excavator_state.txt`;
- `nether_builder_state.txt`;
- `coordinate_state.txt`;
- `settings.txt`;
- `inventory_state.txt`;
- `ore_targets.txt`.

Az állapotírás ideiglenes fájlt és biztonsági másolatot használ. A turtle-t
egy váratlan leállás után ne mozgasd el kézzel. A központi menü `Felbehagyott
munka` pontja csak a valóban aktív mentéseket listázza.

## Futás közbeni kijelzés és vezérlés

A státuszképernyő minden frissítéskor törlődik és ugyanazokat a sorokat írja
újra: feladat, fázis, haladás, pozíció/irány, fuel, inventory, ellátmány,
eltelt idő, hátralévő becslés és figyelmeztetések. Így a terminál nem telik meg
állapotüzenetekkel.

- `Q` vagy `Ctrl+T`: biztonságos leállítás kérése;
- `S`: azonnali állapotfrissítés a régi közvetlen feladatindításnál.

A branch miner, a területásó és a Nether-építő leállításkor hazatér, lepakol és
ment. A koordinátás feladat biztonságosan megáll és menti az aktuális világpozíciót.

Az indulási összefoglaló először képlettel kiszámolja a várható műveletszámot,
majd ezt megszorozza az alapértelmezett `0,8 mp/művelet` értékkel:

```text
induló idő = várható műveletek × 0,8 mp
```

A `work_estimator.lua` külön számolja a mozgást, függőleges mozgást, ásást,
fordulást, lerakást és – ahol szükséges – az ellenőrzéseket. Példák:

```text
Branch főút = hossz × (oda-vissza mozgás + magasság szerinti ásás)
Oldalágak = elágazások × 2 oldal × ághossz × oda-vissza út
3×3 szelet = 5 mozgás + 9 ásás + 6 fordulás
Terület = szélesség × mélység × magasság + bejárás + hazatérés
Lépcsőfok = 4 mozgás + 4 ásás + 1 építés
Védett alagútcella = 4 mozgás + 2 ásás + legfeljebb 6 építés
Koordinátaút = |ΔX| + |ΔY| + |ΔZ| + irányváltások
```

Az érctelep mérete, a folyadék, kavics, mob, inventory-ürítés vagy más váratlan
esemény előre nem ismert. Futás közben a program ezért méri az egyes
művelettípusok tényleges idejét. Akadály vagy figyelmeztetés esetén növeli a
tanult járulékos szorzót, majd a még hátralévő képletet azonnal újraszámolja.
A dashboard egyszerre mutatja a hátralévő várható műveletszámot és az adaptív
időt, például: `1842 muv. / kb. 00:24:34`.

## Helyzetkezelés

A `situation_manager.lua` közös, strukturált eredményt ad a feladatoknak.
Kezeli az ismételhető akadályokat, a fáklya tartalék elhelyezési sorrendjét,
valamint a felülről, alulról vagy elölről érzékelt víz/láva tömítését. Egy
nem létfontosságú hiba – például egy kihagyott fáklya – alapból nem szakítja
félbe a teljes munkát. Navigációs bizonytalanságnál viszont a program ment és
megáll, nem talál ki ellenőrizetlen pozíciót.

## Indítási napló

Az `action_log.lua` az `action_log.txt` fájlba csak az indítás időpontját, a
feladat nevét és az induláskori fuel-szintet fűzi hozzá. Mozgást vagy fordulást
nem naplóz.

## Fájlok

| Fájl | Szerep |
| --- | --- |
| `main.lua` | Központi indító és menürendszer. |
| `ui.lua` | Nyilas, kattintós menük és strukturált dashboard. |
| `settings.lua` | Verziózott közös beállítások. |
| `navigation.lua` | Relatív pozíció, útvonal, mozgás és helyreállítás. |
| `coordinate_navigation.lua` | KÍSÉRLETI világkoordinátás útvonaltervezés. |
| `situation_manager.lua` | Akadály-, folyadék- és fáklyahibák kezelése. |
| `telemetry.lua` | Eltelt idő, mért műveletidő és ETA. |
| `work_estimator.lua` | Módonkénti műveletszám-képletek és induló időbecslés. |
| `state_store.lua` | Atomi JSON-állapotmentés és visszaállítás. |
| `job_request.lua` | A központi menü egyszer használható feladatátadása. |
| `branch_miner.lua` | Branch mining és egyenes 3×3. |
| `excavator.lua` | KÍSÉRLETI területásás. |
| `nether_builder.lua` | Útvonalkészítés: lépcső, védett és sima 1×2-es alagút. |
| `coordinate_task.lua` | KÍSÉRLETI koordinátás feladat futtatója. |
| `inventory_manager.lua` | KÍSÉRLETI kapacitásalapú inventory-kezelés. |
| `torch_manager.lua` | KÍSÉRLETI automatikus fáklyázás. |
| `ore_scanner.lua` | KÍSÉRLETI érclista és érctelepkövetés. |

## Downloader: GitHub vagy Pastebin

A `downloader.lua` elején választható a forrás:

```lua
local DOWNLOAD_SOURCE = "github" -- vagy: "pastebin"
```

Publikus GitHub-repónál nem kell token. Alapbeállítással a downloader nem
küld hitelesítési fejlécet. Privát repóhoz később külön beállítható tokenfájl.

```text
downloader                 # minden GitHub-komponens
downloader main            # a teljes központi rendszer
downloader branch          # branch miner és függőségei
downloader excavator       # területásó és függőségei
downloader nether          # útvonalkészítő és függőségei (régi parancsnév)
downloader coordinate      # koordinátás navigáció és függőségei
downloader downloader      # csak a downloader
```

Az új modulokhoz jelenleg nincs Pastebin ID, ezért a teljes moduláris rendszer
telepítéséhez a GitHub-forrás szükséges. A letöltés először ideiglenes fájlba
történik, és a működő példány csak sikeres letöltés után cserélődik le.
A downloader saját frissítésekor az új Lua-kód szintaxisát is ellenőrzi;
hibás példányt nem telepít.

## Tesztelés

A `tests/navigation_test.lua` mock turtle-lel ellenőrzi a relatív mozgást, az
egzakt hazatérést, a félbemaradt tranzakció helyreállítását, az akadály utáni
újrapróbálást és az észak=`-Z` világkoordináta-konvenciót.
