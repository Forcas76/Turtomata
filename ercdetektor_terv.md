# Kísérleti ércdetektáló – fejlesztési terv

## Cél

A branch mining mód opcionális, kísérleti kiegészítést kap. Miután a turtle egy adott főági pontnál mindkét oldalágat kiásta, végigellenőrzi az ágak padlóját, mennyezetét, oldalfalait és végét. A felhasználó által kiválasztott érceket korlátozott mélységben követi, majd pontosan visszatér arra az ágpontjára és abba az irányba, ahonnan az érckitermelést elkezdte.

A funkció első körben csak az 1×2 és 1×3 branch mining módhoz készül el. A 3×3-as egyenes alagút és a területásás később külön adaptálható.

## Menürendszer

A bányászati módhoz tartozó adatok után jelenjen meg:

```text
KISERLETI erckereses
1. Kikapcsolva
2. Bekapcsolva
```

Bekapcsoláskor külön ércválasztó nyílik meg:

```text
Keresett ercek
[x] Gyemant
[ ] Smaragd
[x] Vas

< Elozo   Kovetkezo >
+ Uj blokk
- Torles
  Kesz
```

A rövid képernyők miatt a lista lapozható. A sorok kattintással vagy billentyűzettel is kapcsolhatók.

- Advanced Turtle esetén használható a `mouse_click` esemény, tehát valódi kattintható gombok és jelölőnégyzetek készíthetők.
- Normál turtle nem ad `mouse_click` eseményt, ezért mindig maradjon számbillentyűs, nyílbillentyűs és Enteres vezérlés is.
- Az eseménykezelő egyszerre figyelje a `mouse_click`, `key` és `char` eseményeket; ne várjon kizárólag egérkattintásra.
- A végleges összegző képernyő után továbbra is külön Enter indítsa el a turtle-t.

Az ércdetektálás további rövid beállításai:

```text
Max melyseg [4]:
Max erc/telep [16]:
```

Az Enter mindkét esetben elfogadja az alapértéket. A két korlát megakadályozza, hogy a turtle egy nagy vagy modolt érctelepet korlátlanul kövessen.

## Érclista kezelése

A turtle technikailag blokkazonosítókat keres, nem a kibányászott tárgy nevét. Például:

```text
minecraft:diamond_ore
minecraft:deepslate_diamond_ore
modazonosito:tin_ore
```

Az ércválasztó tudja:

1. megjeleníteni a beépített vanilla listát;
2. egy érchez csoportosan kijelölni a normál és deepslate változatot;
3. új blokkazonosítót felvenni;
4. meglévő saját elemet törölni;
5. a kiválasztást tartósan elmenteni.

Az új azonosító formátuma `namespace:block_name`. Mentés előtt kisbetűssé kell alakítani, a szóközt és hibás formátumot pedig el kell utasítani.

A turtle API nem ad teljes Minecraft/mod blokkregiszter-listát, ezért a menü alapja egy beépített vanilla lista és a kézzel hozzáadott modolt blokkok listája lesz. Későbbi bővítésként az inspect során már látott blokkazonosítók külön „Felfedezett blokkok” listába gyűjthetők.

Javasolt adatfájl:

```text
ore_targets.txt
```

A fájl egyetlen, felülírt serializált táblát tartalmazzon. Példa:

```lua
{
  version = 1,
  selected = {
    ["minecraft:diamond_ore"] = true,
    ["minecraft:deepslate_diamond_ore"] = true
  },
  custom = {
    "modazonosito:tin_ore"
  }
}
```

Az `inspect`, `inspectUp` és `inspectDown` által visszaadott `data.name` értéket kell összevetni a `selected` táblával. Első verzióban pontos névegyezés legyen; az olyan változó modtagek, mint a `c:ores` vagy `forge:ores`, csak későbbi külön opcióként kerüljenek be.

## Munkafolyamat egy főági beásásnál

Az ajánlott sorrend:

1. bal oldalág teljes kiásása;
2. jobb oldalág teljes kiásása;
3. bal ág teljes átvizsgálása és érckitermelése;
4. jobb ág teljes átvizsgálása és érckitermelése;
5. az ágak fáklyáinak lerakása a visszaúton;
6. visszatérés a főág középvonalára és a főági munka folytatása.

Az ércvizsgálatnak a fáklyázás előtt kell megtörténnie. Így egy később kibányászott falblokk nem üti le a már lerakott fáklyát. Ha a meglévő kódban az oldalági fáklyázás jelenleg közvetlenül az ág kiásása után fut, azt külön, később meghívható lépésre kell bontani.

## Az oldalág átvizsgálása

A turtle minden járható ágcella mellett ellenőrizze az elérhető felületeket:

- padló: `inspectDown()`;
- mennyezet: `inspectUp()`;
- bal és jobb oldalfal: elfordulás, `inspect()`, majd az eredeti irány visszaállítása;
- az ág végfalának minden elérhető magassága;
- 1×2-es ágban mindkét járatszint oldalfalait;
- 1×3-as ágban mindhárom járatszint oldalfalait, továbbá a legalsó padlót és a legfelső mennyezetet.

Minden vizsgálati pont előtt rögzíteni kell:

- a főági beásás sorszámát;
- az oldalág oldalát (`left` vagy `right`);
- az ágon belüli távolságot;
- a függőleges szintet;
- a turtle irányát.

A felső szintek vizsgálata után a turtle mindig ugyanarra a középvonalra, szintre és irányba álljon vissza. Így a következő ágcella feldolgozása nem függ attól, hol talált előzőleg ércet.

## Érctelep követése

Ha egy vizsgált blokk neve szerepel a kiválasztott listában, a turtle egy korlátozott mélységi keresést indít.

Az első változat működése:

1. elmenti az ágon lévő kezdőpozíciót és irányt;
2. ellenőrzi az üzemanyagot és az inventory befogadóképességét;
3. kibányássza a kiválasztott ércet, majd belép a helyére;
4. az új cellából mind a hat irányban keres további, közvetlenül kapcsolódó kiválasztott ércet;
5. mélységi bejárással követi az összefüggő telepet;
6. minden kitérő után az eltárolt út fordítottját járja be;
7. pontosan visszaáll az oldalági kezdőcellába és eredeti irányba;
8. folytatja az ág ellenőrzését a következő felülettel vagy cellával.

Csak közvetlenül érzékelt, kijelölt ércet szabad kibányászni. A kereső ne bontson találomra követ vagy más köztes blokkot rejtett ércek után.

A bejárás útvonalvermet használjon. Minden sikeres mozgás bekerül a verembe a hozzá tartozó fordított mozgással együtt. Például az előrelépés visszaútja hátralépés, a felfelé lépésé lefelé lépés. Az elfordulások után mindig explicit módon vissza kell állítani az előző tájolást.

A keresést leállító feltételek:

- elérte a `Max melyseg` értéket;
- elérte a `Max erc/telep` értéket;
- nincs több közvetlenül csatlakozó kiválasztott érc;
- nincs elég üzemanyag a biztonságos visszaúthoz;
- a következő érctermék már nem férne az inventoryba;
- a blokk nem bontható vagy a helyére nem lehet biztonságosan belépni;
- a felhasználó leállítást kér.

Hurok elkerüléséhez az aktuális érctelepen belül relatív koordináták alapján `visited` táblát kell vezetni.

## Inventory, üzemanyag és ládák

Minden érc kibányászása a közös, biztonságos ásófüggvényen keresztül történjen.

- Ha a kísérleti inventory-figyelő aktív, a detektált érc várható dropjára ugyanazt a férőhely-ellenőrzést kell használni: csak akkor induljon haza, ha a termék már nem férne be.
- Ha az inventory-figyelő ki van kapcsolva, legalább a hagyományos teljes-inventory ellenőrzés maradjon aktív.
- A szén számára fenntartott 1-es, valamint bekapcsolt fáklyázáskor a fáklyák számára fenntartott 2-es slot szabályai változatlanok.
- Érckitérő előtt a szükséges fuel érték tartalmazza a kitérőből az ághoz vezető utat, az ágtól a bázisig vezető utat és a biztonsági tartalékot.

Ha az érctelep közepén kell üríteni vagy tankolni, nem szabad tömör falon keresztüli koordinátás rövidítést használni. A turtle:

1. visszajárja az érckitérő eltárolt útját az ágig;
2. a már kiásott oldalágon és főágon hazamegy;
3. ürít és tankol;
4. visszamegy ugyanahhoz az oldalági horgonyponthoz;
5. újrajátssza az elmentett érckitérő útját;
6. folytatja a félbehagyott keresést.

## Leállítás és folytatási állapot

Az ércdetektáló a meglévő leállító funkciót használja. Leállításkor először megpróbál visszajutni az aktuális érckitérőből az oldalágba, majd onnan a bázisra.

A folytatási fájlba az általános bányászati állapot mellett bekerül:

```lua
oreScan = {
  active = true,
  branchIndex = 12,
  side = "left",
  branchStep = 7,
  scanLevel = 1,
  surface = "right",
  anchor = { x = 0, y = 0, z = 0, dir = 0 },
  veinPath = { "F", "U", "F" },
  veinVisited = {},
  veinMined = 3
}
```

Állapotmentés szükséges:

- az oldalág vizsgálatának megkezdése előtt;
- minden vizsgálati cella és felület után;
- minden érckitérő megkezdése előtt;
- minden sikeres ércbontás és mozgás után;
- az ághoz való visszatérés után;
- ürítés/tankolás előtti hazatéréskor és a munkahelyre való visszaéréskor.

Újraindítás után a turtle ne feltételezze, hogy közvetlen koordinátás út szabad. Az elmentett érckitérő-út alapján előbb biztonságosan álljon vissza az oldalágba, vagy ha már a bázison van, a főág–oldalág útvonalon menjen vissza a horgonyponthoz.

## Javasolt fájlok és kódstruktúra

Új fájl:

```text
ore_scanner.lua
```

Felelősségei:

- érclista betöltése, mentése és ellenőrzése;
- kattintható/billentyűs érckiválasztó menü;
- blokkazonosító egyeztetése;
- oldalág felületeinek átvizsgálása;
- korlátozott érctelep-bejárás;
- útvonalverem és visszatérés;
- ércvizsgálati runtime állapot serializálása.

Módosítandó fájlok:

- `branch_miner.lua`: kapcsoló, menü, munkafolyamat és folytatási állapot integrálása;
- `torch_manager.lua`: az oldalági fáklyázás külön, később meghívható menetre bontása;
- `inventory_manager.lua`: közös ásás előtti férőhely-ellenőrzés használata;
- `downloader.lua`: az új modul és szükség esetén az alap érclista letöltése;
- `README.md`: menümagyarázat, Advanced Turtle kattintás és billentyűs tartalékvezérlés;
- `action_log.lua`: induláskor az `erckereses=be/ki` állapot naplózása, részletes mozgásnapló nélkül.

Beállítási kulcsok:

```lua
oreScanEnabled = false
oreScanMaxDepth = 4
oreScanMaxBlocks = 16
oreTargetsFile = "ore_targets.txt"
```

## Hibakezelés

- Ha `inspect` után a blokk megváltozik vagy eltűnik, a turtle újraellenőriz, és nem számolja kibányászott ércnek.
- Ha kavics vagy homok esik az útba, csak akkor bontsa el, ha az a már megnyitott visszaút helyreállításához szükséges; utána újraellenőrizze a pozíciót.
- Folyadékba ne lépjen automatikusan.
- Ha egy érctől nem kap használható inspect-adatot, hagyja ki és folytassa az átvizsgálást.
- Ha nem tud visszalépni a tárolt útvonalon, mentse az állapotot, jelezze a hiba pontos helyét, és ne törölje a folytatási adatot.

## Tesztlista

- Advanced Turtle: kattintás, lapozás, kijelölés és Kész gomb.
- Normál turtle: ugyanaz a menü kizárólag billentyűzettel.
- Saját blokkazonosító hozzáadása, törlése, hibás formátum és újraindítás utáni megőrzése.
- 1×2 és 1×3 ág minden oldalfala, padlója, mennyezete és végfala.
- Kijelölt és nem kijelölt ércek egymás mellett.
- Egyenes, kanyarodó, felfelé és lefelé futó érctelep.
- Kör alakban kapcsolódó ércek: a `visited` lista akadályozza meg az ismétlést.
- Max mélység és max blokkszám betartása.
- Inventory megtelik egy érckitérő közepén.
- Fuel kritikussá válik egy érckitérő közepén.
- Leállítási parancs és újraindítás az oldalágban, illetve az érctelepben.
- Kavics, folyadék, törhetetlen blokk és mozgást akadályozó entitás.
- Fáklyák csak az ércvizsgálat után kerülnek a végleges helyükre.
- A turtle minden kitérő után ugyanarra az ágcella-koordinátára, szintre és irányba tér vissza.

## Elfogadási feltételek

A funkció akkor tekinthető első kísérleti verzióként késznek, ha:

- teljesen ki- és bekapcsolható;
- a keresett ércek listája menüből szerkeszthető és tartósan mentődik;
- Advanced Turtle esetén kattintható, normál turtle esetén billentyűzettel végig használható;
- csak a kijelölt blokkokat követi;
- mindkét oldalág minden előírt felületét átvizsgálja;
- a korlátokat betartva követi az összefüggő érctelepet;
- minden érckitérő után pontosan az eredeti ágponton folytatja;
- ürítés, tankolás, kézi leállítás és újraindítás után is vissza tud állni a félbehagyott munkára;
- az ércvizsgálat nem teszi tönkre az oldalági fáklyákat.

## CC:Tweaked hivatkozások

- [mouse_click esemény](https://tweaked.cc/event/mouse_click.html) – csak Advanced Computer/Turtle terminálon érhető el.
- [Blokkadatok](https://tweaked.cc/reference/block_details.html) – az inspect eredményének `name`, `state` és `tags` mezői.
- [Turtle API](https://tweaked.cc/module/turtle.html) – `inspect`, `inspectUp`, `inspectDown`, mozgás és ásás.
