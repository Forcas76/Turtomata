# Inventory-kezelés és gazdaságos lepakolás terve

## Cél

A turtle ne csak akkor induljon haza, amikor minden bányászslot teljesen
megtelt, hanem még azelőtt, hogy a következő kibányászott blokk vagy drop már
nem férne el. Ugyanakkor ne használjon egyszerű százalékos határt, mert az
feleslegesen korai hazatéréseket okozna.

A javasolt megoldás minden bányászmódnál közös legyen:

- branch mining 1×2;
- branch mining 1×3;
- egyenes 3×3-as alagút;
- területásás;
- a későbbi kísérleti ércfelderítés.

## A jelenlegi működés és a hiba oka

A programban jelenleg van inventory-ellenőrzés. A `branch_miner.lua` és az
`excavator.lua` az alábbi logikával vizsgálja a bányászslotokat:

```lua
if turtle.getItemSpace(slot) > 0 then
    return false
end
```

Ez nem minden esetben jelenti azt, hogy a következő drop valóban elfér.
Például lehet minden használható slotban más-más, 63 darabos stack. A
slotokban van egy-egy szabad hely, ezért az inventory nem számít tele, de egy
új blokkfajta számára nincs üres slot.

Ez megmagyarázhatja, hogy a turtle miért nem indul mindig vissza időben
lepakolni.

## Alapelv

Nem azt kell kérdezni, hogy **van-e valahol szabad hely**, hanem azt, hogy:

> A következő várható drop biztonságosan elhelyezhető-e valamelyik
> bányászslotban?

A döntéshez a program egy memóriában tartott inventory-képet használ. Ennek
tartós másolata az `inventory_state.txt` fájlba kerül, egyetlen JSON-sorban,
mindig felülírva az előző állapotot.

## Fenntartott és bányászslotok

- Az 1-es slot mindig az üzemanyagé.
- Bekapcsolt fáklyázásnál a 2-es slot mindig a fáklyáé.
- Fáklyázás nélkül a 2–16. slot használható bányászatra.
- Fáklyázással a 3–16. slot használható bányászatra.
- A fenntartott slotok tartalma nem számítható bele a kibányászott
  tárgyak szabad kapacitásába.

## Az inventory-pillanatkép tartalma

Az `inventory_state.txt` javasolt felépítése:

```json
{"version":1,"updated":0,"reason":"indulas","firstMiningSlot":3,"emptyMiningSlots":12,"slots":{"1":{"name":"minecraft:coal","count":32,"space":32},"2":{"name":"minecraft:torch","count":64,"space":0}},"itemTotals":{"minecraft:coal":32,"minecraft:torch":64},"seenBlocks":{"minecraft:stone":true},"blockDrops":{"minecraft:stone":"minecraft:cobblestone"}}
```

A fájl tartalmazza:

- slotonként az item nevét, darabszámát és fennmaradó helyét;
- a használható üres bányászslotok számát;
- itemtípusonként az összes darabszámot és szabad stackhelyet;
- a már látott blokktípusokat;
- a futás alatt megtanult blokk→drop kapcsolatokat;
- a frissítés okát.

A fájlt először egy ideiglenes fájlba kell kiírni, majd átnevezéssel
cserélni. Így egy áramkimaradás kisebb eséllyel hagy félbehagyott JSON-t.

## Fontos pontosítás: blokk neve és drop neve

Az `inspect` által visszaadott blokknév nem mindig azonos azzal az itemmel,
amely bányászáskor az inventory-ba kerül. Például:

```text
minecraft:stone -> minecraft:cobblestone
```

Ezért az a szabály, hogy "a blokk neve nincs az inventory-ban", önmagában
nem elég biztos. Az ötletet az alábbi módon érdemes megvalósítani:

1. A turtle bányászás előtt `inspect` segítségével azonosítja a blokkot.
2. Ha ezt a blokktípust még nem látta, teljes inventory-pillanatképet készít.
3. A sikeres `dig`, `digUp` vagy `digDown` után ismét beolvassa az inventory-t.
4. A két pillanatkép különbségéből megpróbálja megtanulni a drop
   itemnevét.
5. A blokk→drop kapcsolatot memóriában és a TXT-ben is elmenti.
6. Ha a blokk többféle itemet dob, vagy a különbség nem egyértelmű, a blokk
   `ismeretlen drop` besorolást kap, és a biztonságosabb szabály érvényes rá.

## Mikor kell frissíteni az inventory-képet?

Kötelező teljes frissítés:

1. minden programindításkor;
2. minden automatikus folytatáskor;
3. minden alkalommal, amikor a turtle a ládáknál befejezte a lepakolást,
   tankolást és esetleges fáklyafelvételt, közvetlenül az elindulás előtt;
4. korábban nem látott blokktípus felismerésekor, a bányászás előtt
   és után;
5. minden `drop`, `suck`, `refuel`, fáklyalerakás vagy más, inventory-t
   módosító művelet után;
6. hazatérési döntés előtt, hogy a program ne elavult adatok alapján forduljon
   vissza;
7. időszakos biztonsági ellenőrzésként, alapértelmezetten 16 sikeres
   bányászásonként.

A memóriában tartott kép minden releváns művelet után frissülhet, de a
TXT-fájlt csak akkor kell újraírni, ha az inventory tartalma, a tanult
blokk→drop tábla vagy a frissítés oka ténylegesen megváltozott. Ez csökkenti a
felesleges lemezírásokat.

## Gazdaságos hazatérési döntés

### Ismert drop esetén

A turtle folytathatja a bányászást, ha:

- van olyan bányászslot, amelyben ugyanaz az item van és elegendő hely
  maradt benne; vagy
- van legalább egy üres bányászslot.

Ha egyik feltétel sem teljesül, a blokk kiütése előtt haza kell térni.

### Új vagy ismeretlen drop esetén

Ismeretlen dropot csak akkor szabad kibányászni, ha van legalább egy teljesen
üres bányászslot. Ha nincs, a turtle még a blokk kiütése előtt visszatér
lepakolni.

### Biztonsági puffer

Alapértelmezetten egy üres bányászslot legyen biztonsági puffer az ismeretlen,
többszörös vagy váratlan dropok számára.

- Ha a következő ismert drop meglévő stackbe fér, a puffer megőrizhető, és
  a munka folytatható.
- Ha a következő drop elfoglalná az utolsó üres slotot, a blokk még
  kibányászható, de utána azonnal lepakolási visszatérést kell jelölni.
- Ismeretlen vagy várhatóan több darabot adó ércnél az utolsó üres slotot
  nem szabad kockáztatni: előbb le kell pakolni.

Ez gazdaságosabb egy fix, például 80%-os telítettségi határnál, mert a
turtle kihasználja a részben töltött stackeket, de nem veszít el új itemtípust.

## Stackek rendezése

Hazatérés előtt a program egyszer megpróbálhatja összevonni az azonos
itemeket a bányászslotokban a `transferTo` segítségével. Ha ezzel felszabadul
egy slot, a munka folytatható, és elkerülhető egy felesleges oda-vissza út.

A rendezés szabályai:

- az 1-es fuel slothoz nem nyúlhat;
- bekapcsolt fáklyázásnál a 2-es slothoz nem nyúlhat;
- csak azonos itemnevű és azonos részletadatú stackeket vonhat össze;
- rendezés után kötelező az inventory-kép frissítése.

## A biztonságos bányászási folyamat

Minden `dig`, `digUp` és `digDown` közös ellenőrzött függvényen keresztül
fusson:

```text
inspect
  -> várható drop meghatározása
  -> inventory-pillanatkép ellenőrzése
  -> szükség esetén stackek összevonása
  -> ha nem fér el: mentés, hazatérés, lepakolás, visszatérés
  -> megfelelő gyűjtőslot kiválasztása
  -> dig / digUp / digDown
  -> inventory-kép frissítése
  -> esetleges blokk→drop kapcsolat megtanulása
  -> telítettség újraértékelése
```

A gyűjtőslot kiválasztása fontos: ismert dropnál először az azonos,
részben töltött stacket kell kiválasztani, új dropnál pedig egy üres
bányászslotot.

## Hazatérés és folytatás

Ha lepakolás szükséges:

1. a turtle elmenti az aktuális pozíciót, irányt, munkafázist és azt, hogy
   melyik blokk kiütése előtt állt meg;
2. visszatér a kezdőpontra;
3. lepakolja a bányászott tárgyakat;
4. feltankol, és igény esetén fáklyát vesz fel;
5. teljesen újraolvassa az inventory-t;
6. felülírja az `inventory_state.txt` tartalmát;
7. csak ezután indul el a mentett munkapontra;
8. visszatérve ismét `inspect` segítségével ellenőrzi, hogy a korábban
   kihagyott blokk még ott van-e, majd folytatja a munkát.

Az inventory miatti hazatérés ugyanazt a meglévő `serviceAndResume`
mechanizmust használja, de a bányászási ellenőrzőpontot a blokk kiütése előtt
kell rögzíteni.

## Fájl és modul felosztása

Javasolt új modul:

```text
inventory_manager.lua
```

Fő feladatai:

```lua
scan(config)
refresh(config, reason)
saveSnapshot(reason)
loadLearnedDrops()
canAccept(blockData)
selectCollectionSlot(blockData)
recordDigResult(blockData, beforeSnapshot)
compact(config)
shouldReturn(blockData)
```

Tartós állapot:

```text
inventory_state.txt
```

A `branch_miner.lua` és az `excavator.lua` ugyanazt a modult használja, hogy
ne alakuljon ki két eltérő inventory-logika.

## Hibakezelés

- Hiányzó vagy sérült `inventory_state.txt` esetén a program ne álljon le;
  olvassa be újra a turtle valódi inventory-ját, és hozza létre újra a
  fájlt.
- A TXT soha nem lehet elsődleges igazságforrás. Programindításkor és a
  ládáktól való induláskor mindig a turtle valódi inventory-ja az irányadó.
- Ha az inventory tartalma váratlanul eltér a mentéstől, a valós tartalom
  felülírja a fájlt.
- Ha a leadóláda megtelt, a turtle ne induljon vissza dolgozni, hanem írjon ki
  egyértelmű hibát.
- Ha egy blokk dropja nem azonosítható biztosan, a program ismeretlen dropként
  kezelje, ne becsülje optimistán a szabad helyet.

## Állapotkijelzés

Az `S: allapot` kimenete egészüljön ki:

```text
Inv: 11/14 slot
Ures: 3
Puffer: 1
Kovetkezo: minecraft:cobblestone
Kapacitas: 47
```

Ha a turtle lepakolni indul:

```text
Hazateres: nincs hely az uj dropnak
Blokk: minecraft:deepslate_diamond_ore
```

## Javasolt megvalósítási sorrend

1. Közös `inventory_manager.lua` modul és pillanatkép elkészítése.
2. Atomi `inventory_state.txt` mentés és sérült fájl helyreállítása.
3. Fenntartott slotok és tényleges bányászkapacitás kezelése.
4. Ismert, új és ismeretlen dropok kapacitásvizsgálata.
5. Stackösszevonás a felesleges hazatérések csökkentésére.
6. Közös, ellenőrzött dig-wrapper elkészítése mindhárom irányhoz.
7. Integráció a `branch_miner.lua` minden bányászó műveletébe.
8. Integráció az `excavator.lua` minden bányászó műveletébe.
9. Mentés, hazatérés és pontos folytatás bekötése.
10. Állapotkijelzés és README frissítése.
11. Szimulált tesztek, majd játékon belüli próba.

## Kötelező tesztesetek

- Minden bányászslot üres.
- Egy meglévő stackbe még befér a következő drop.
- Minden slot foglalt, de mindegyik stack csak 63 darabos és más itemet
  tartalmaz.
- Nincs üres slot, de az ismert drop egyik meglévő stackbe befér.
- Az utolsó üres slotot egy ismert drop foglalná el.
- Az utolsó üres slot előtt ismeretlen blokk jelenik meg.
- Egy blokk több itemet dob.
- A blokk neve eltér a drop nevétől, például kő és zúzottkő.
- Fáklyázás be- és kikapcsolva.
- Az 1-es fuel slotban nem éghető tárgy van.
- A 2-es fáklyaslot kiürül.
- A leadóláda megtelik lepakolás közben.
- Újraindítás közvetlenül egy új blokk felismerése előtt és után.
- Inventory miatti hazatérés egy oldalág, 3×3-as szelet, területásás
  és későbbi ércfelderítés közben.

## Elfogadási feltételek

- A turtle nem üt ki olyan blokkot, amelynek várható dropja nem fér el.
- Egy új blokktípus első észlelésekor frissíti az inventory-képet.
- Minden, ládáktól történő elindulás előtt a valódi inventory alapján
  felülírja az `inventory_state.txt` fájlt.
- A részben töltött, megfelelő stackeket kihasználja, ezért nem tér haza
  pusztán egy fix slot- vagy százalékhatár miatt.
- Stackösszevonással elkerüli a szükségtelen lepakoló utakat.
- Hazatérés után ugyanazon a munkaponton, a helyes irányban és a kihagyott
  blokk előtt folytatja a munkát.
- A fuel- és fáklyaslot szabályai változatlanul megmaradnak.
- Sérült vagy elavult TXT miatt nem veszít tárgyat: mindig a turtle valódi
  inventory-ja az elsődleges adatforrás.
