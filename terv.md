# Kísérleti oldalág-ércfelderítés terve

## Cél

A branch mining kapjon egy opcionális, **KÍSÉRLETI** funkciót. Ha be van
kapcsolva, a turtle a bal és jobb oldalág elkészítése után végignézi az
alagút falait minden kiásott magassági szinten. Ha közvetlenül az alagút
mellett ércet talál, kibányássza, majd folytatja az ellenőrzést.

A funkció alapértelmezetten legyen kikapcsolva, és a meglévő bányászati
működést kikapcsolt állapotban semmilyen módon ne változtassa meg.

## Menü és beállítás

A beállítás csak a `Branch 1x2` és `Branch 1x3` módoknál jelenjen meg,
az oldalágak adatainak megadása után:

```text
KISERLETI erckereses:
> Kikapcsolva
  Bekapcsolva
```

Mentett konfigurációs kulcs:

```lua
config.oreScanEnabled = false
```

Az összefoglaló képernyőn is jelenjen meg:

```text
Erckereses: KI
```

vagy:

```text
Erckereses: KISERLETI
```

Az automatikus folytatás a mentett értéket használja. Régi mentésnél a
hiányzó beállítás automatikusan `false` legyen.

## Az ellenőrzés sorrendje

1. A turtle a jelenlegi működéssel teljesen kiássa az egyik oldalágat.
2. Az ág végén megkezdi az ércfelderítő visszautat.
3. Minden alagútpozíción ellenőrzi az alsó, majd a felső szintet.
4. `Branch 1x2` módban két, `Branch 1x3` módban mindhárom kiásott
   magassági szintet ellenőrzi.
5. Egy szinten a menetirány szerinti bal és jobb oldalfalat vizsgálja meg.
6. Az alsó szinten a padlót, a legfelső szinten a mennyezetet is
   ellenőrzi.
7. Az oldalág végfalát minden magasságban egyszer megvizsgálja.
8. Az ellenőrzés után mindig visszaáll az adott alagútpozícióra,
   magasságra és eredeti irányba.
9. A fáklyákat csak a teljes ércfelderítés után, a már elkészült
   oldalágban rakja le. Így az ellenőrzés nem üti ki a frissen lerakott
   fáklyákat.
10. Az egyik ág teljes lezárása után következik a másik oldalág.

## Érc felismerése

Az ellenőrzéshez a `turtle.inspect()`, `turtle.inspectUp()` és
`turtle.inspectDown()` függvényeket kell használni. Egy blokk akkor számítson
ércnek, ha az alábbi feltételek valamelyike teljesül:

- a blokk neve `_ore` végződésű;
- szerepel a `forge:ores` vagy `c:ores` tag alatt;
- szerepel egy külön kivétellistában, például
  `minecraft:ancient_debris`.

Az ércfelismerés egyetlen, külön `isOre(blockData)` függvényben legyen,
hogy modpackfüggő ércek később egyszerűen felvehetők legyenek. Ismeretlen
vagy nem érc blokkokat a felderítés nem üt ki.

Az első kísérleti verzió csak az alagútból közvetlenül látható, egy
blokk mélyen lévő ércet bányássza ki. Nem indul el rekurzívan az
érctelérben, mert az jelentősen bonyolítaná a biztos hazatalálást és a
folytatási állapotot.

## Navigáció

Az oldalirányú vizsgálat menete:

1. eredeti irány eltárolása;
2. balra vagy jobbra fordulás;
3. `inspect`, majd érc esetén `dig`;
4. visszafordulás az eredeti irányba;
5. pozíció- és irányellenőrzés.

A felső szintek ellenőrzéséhez a turtle ugyanazon az `x/z` koordinátán
mozogjon fel, majd az ellenőrzés után térjen vissza az alagút alsó szintjére.
Minden mozgás a meglévő pozíció- és iránykövető függvényeken keresztül
történjen.

## Üzemanyag és inventory

- A felderítés függőleges mozgásainak költsége kerüljön bele a munka
  előtti üzemanyag-becslésbe.
- Minden új pozíció előtt maradjon biztosítva a kezdőpontra vezető út,
  a beállított `Fuel tartalek` megtartásával.
- Ha az inventory az érc kibányászása közben megtelik, a turtle mentse el
  a felderítési ellenőrzőpontot, térjen haza, pakoljon le, tankoljon fel,
  majd ugyanahhoz az ellenőrzési ponthoz térjen vissza.
- Az 1-es fuel slot és az opcionális 2-es fáklyaslot szabályai nem
  változhatnak.

## Mentés és automatikus folytatás

A jelenlegi állapotmentést ki kell egészíteni azzal, hogy egy megszakítás
után ne induljon újra a teljes oldalág-vizsgálat. Mentendő adatok:

```lua
runtime.oreScan = {
    active = false,
    side = "bal",       -- "bal" vagy "jobb"
    branchStep = 0,     -- az oldalág aktuális pozíciója
    layer = 0,          -- 0 = alsó szint
    surface = "left",  -- left, right, floor, ceiling vagy end
}
```

Minden mozgás, sikeres érckibányászás és ellenőrzött felület után
frissüljön a mentés. A felderítés befejezésekor az `active` érték legyen
`false`.

A mentési formátum kapjon új verziót. A régi mentések betöltésekor az
ércfelderítés legyen kikapcsolva, így a meglévő munkák továbbra is
folytathatók maradnak.

## Futás közbeni kijelzés

Az `S: allapot` parancs az ércfelderítés alatt mutassa legalább ezeket:

```text
Fazis: ercfelderites
Ag: bal
Pozicio: 7/16
Szint: 2/2
Vizsgalat: jobb fal
Talalt erc: 5
```

Az akciónapló továbbra is csak a funkció indítását naplózza. A fordulásokat,
vizsgálatokat és az egyes kibányászott érceket nem kell beleírni.

## Javasolt megvalósítási lépések

1. Menüopció, konfiguráció és összefoglaló kijelzés hozzáadása.
2. Az `isOre` felismerőfüggvény elkészítése.
3. Egyetlen felület biztonságos ellenőrzésének és bányászásának
   megvalósítása.
4. Egy alagútpozíció minden szintjének bejárása.
5. A teljes oldalág visszafelé történő felderítése.
6. A fáklyázási sorrend és a második oldalág bekötése.
7. Üzemanyag-, inventory- és otthoni kiszolgálás integrációja.
8. Részletes ellenőrzőpont mentése és automatikus folytatása.
9. Állapotkijelzés és README menümagyarázat frissítése.
10. Tesztelés szimulált turtle API-val, majd játékon belüli próba.

## Elfogadási feltételek

- Kikapcsolt opcióval a jelenlegi útvonal és működés változatlan.
- Bekapcsolva mindkét oldalágat csak azok teljes kiásása után vizsgálja.
- Az 1×2-es ág mindkét, az 1×3-as ág mindhárom magassági szintjét
  ellenőrzi.
- Csak felismert ércet bányász ki; követ, ládát, fáklyát vagy más
  blokkot nem.
- Az ellenőrzés után a turtle mindig az oldalág alsó szintjén, a helyes
  irányban folytatja a munkát.
- Kevés fuel, megtelt inventory, felhasználói leállítás vagy újraindítás
  esetén biztonságosan hazatér, majd pontosan folytatható a felderítés.
- A fáklyázás az ércfelderítéssel együtt is működik, és a turtle
  nem üti ki a saját fáklyáit.
