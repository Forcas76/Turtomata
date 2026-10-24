# Közös branch mining – egyeztetett célműködés

Ez a fájl a felhasználó által kért működést írja le. Nem a korábbi, külön „Közös munka” menüre és nem a „teljes főág, aztán segédek” megoldásra épül. A cél és a játékban ténylegesen kipróbált működés között a tesztelésig különbség lehet.

## Indítás és beállítás

1. A fő turtle-n: `Branch mining → 1×2 vagy 1×3 → Egyedüli vagy közös`.
2. Ezután ugyanaz a branch-feladatlap jelenik meg mindkét esetben: főág és oldalág mérete, ágköz, üzemanyag, inventory/leadás, érckeresés, fáklyázás és a többi alkalmazható beállítás. A közös mód nem külön bányászati feladatfajta.
3. A közös munkát az első turtle hozza létre. A játékos a computer vagy pocket computer/tablet megfigyelőjén kézzel kiválasztja, melyik eszköz legyen a koordinátor. A segédturtle-öket a játékos egyszer helyben csatlakoztatja és ellenőrzi a sorhelyüket/irányukat; ezután nem kell minden ágat kézzel elindítani.
4. A feladat konfigurációja az egész munkához tartozik. A segédek megkapják/mentik az alkalmazható beállításokat, és a saját bányászati, fáklyázási, érckeresési, inventory- és fuel-rendszerükkel dolgoznak. A koordinátor feladatot és biztonságos útvonaljogot ad, nem mikromenedzseli az ásó műveleteket.

## Munka közbeni viselkedés

1. Az első turtle építi a főágat. Amint egy oldalág kereszteződése elkészült és az odavezető út biztonságosan járható, azt a koordinátornak késznek jelenti. **Nem kell megvárni a teljes főág végét.**
2. A koordinátor a szabad ágakat az elérhető, alkalmas turtle-öknek dinamikusan osztja ki. A korábban csatlakozott és a később csatlakozó segédek is kaphatnak munkát. Egy ág egyszerre csak egy turtle-é lehet.
3. A segéd a kiosztást követően önállóan elindul, megközelíti az ágat, kibányássza a közös beállítások szerint, szükség esetén lead/tankol, majd következő munkát vár. Nem kell áganként új Enter.
   Ha a kész ág után van másik, már járható szabad ág, és az inventory, a fáklya és a biztos hazatérésre számolt fuel engedi, a turtle a régi ág bejáratától közvetlenül az újhoz mehet. A koordinátor az új ágat és az egysávos folyosót tartósan lefoglalja; a régi ág csak az új bejárathoz történt igazolt érkezés után lesz kész. Készlethiánynál vagy szabad ág nélkül a bázisra tér vissza.
4. A fő turtle a főág befejezése és a bázis kiszolgálása után **nem fejezi be a közös munkát**: szabad munkássá válik, és ugyanúgy kap oldalágakat, mint a segédek.
5. A keskeny közös folyosón, a kereszteződésekben és a ládáknál az ütközést a koordinátor forgalmi jogokkal előzi meg. Amíg a fő turtle a főágon halad, a már elkészült, mögötte fekvő ágakban más turtle-ök dolgozhatnak. A fő turtle hazatérését/kiszolgálását és a segédek áthaladását külön egyeztetni kell.
6. Kapcsolatvesztésnél vagy bizonytalan fizikai pozíciónál senki nem kap új mozgási jogot, és egy foglalt ág nem lesz automatikusan „szabad”. Tartós helyi mentés, fizikai ellenőrzés és koordinátori egyeztetés szükséges a biztonságos folytatáshoz.

## Szerephatárok

- **Koordinátor:** nyilvántartja a munkát, a szabad/foglalt/kész ágakat, a résztvevőket és a közös útvonalak/ládák foglalását; a pillanatnyi szabad kapacitás és költség alapján kioszt.
  A teljes munka eltelt és becsült hátralévő idejét a főág, az oldalágak és a jelenleg elérhető munkások alapján frissíti. Ez váratlan érc, forgalmi várakozás és ellátási hiba miatt csak közelítés.
- **Turtle:** maga hajtja végre a hozzá rendelt feladatot a munkakonfigurációval; helyben menti a pozíciót és az ásási haladást. A játékos normál esetben csak felügyel.
- **Fő turtle:** a főág készítése idején külön vezető feladatot lát el; utána ugyanolyan ágásó résztvevő, mint a többi.

## A korábbi implementációból elhagyandó viselkedés

- Külön felső szintű „Közös munka” feladatmenü és külön, négymezős közös konfiguráció.
- Ágak meghirdetése csak a teljes főág kiásása után.
- Segéd ágankénti kézi indítása.
- A fő turtle végleges, passzív félreállítása a főág végén.
- A közös módban az érckeresés és fáklyázás kényszerű kikapcsolása.

## Megvalósításkor különösen ellenőrzendő

- A főágat építő turtle és a mögötte közlekedő segéd tényleges útvonala nem keresztezheti egymást; a vezető váratlan visszaútja sem kerülheti meg a koordinátort.
- A kiosztás, a helyi feladatmentés és a koordinátori ACK újraindítás/ismételt üzenet mellett sem indíthat két turtle-t ugyanarra az ágra.
- Az érc-kitérő ne nyisson át másik kiosztott ág vagy foglalt közös folyosó cellájába.
- A fáklyázás és a lepakolás csak az alkalmazható munkarészhez tartozó konfigurációt használja, és ne állítsa meg az egész csapatot egyetlen sikertelen fáklyalerakás miatt.
