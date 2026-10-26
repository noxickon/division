# Division 2 Datamining – Doku & Update-Anleitung

Stand: 2026-10-26 · Online-Version: https://claude.ai/artifact/TBRbM6sBPiS8FtiFEGrWmo

Die Schadensformeln von The Division 2 stehen als Klartext in den Spieldaten und lassen sich nach jedem Update in rund einer Stunde neu auslesen. Fokus: PvE, PvP-Werte nur als Zusatz. Datenstand: Build vom 09.10.2026. Nächstes Update: 02.11.2026.

## Ergebnisse: die Formeln

Alle Formeln stammen aus `rogue\game system data\juice\attribute\dictionary\*.mdict` (6.986 Attribute). Innerhalb einer Klammer wird addiert, Klammern werden miteinander multipliziert.

### Waffenschaden (`PhysicalDamageMaxFinal`)

```
Waffenschaden = (Grundschaden × max(0.5, BaseMod) + Flat_Typ) × (1 + WD% + Typ% + Talent_WD) × (1 + GearTalent_WD)
```

- **Topf 1 (addiert):** Waffenschaden (Kern-Attribut, Attribute, Brands), Waffentyp-Schaden (z. B. LMG-Schaden), Talente für fehlende Rüstung (Chest), halbes Magazin, wenig Munition.
- **Topf 2 (eigener Multiplikator):** `GearTalentWeaponDamageModBonus`, also Gear-Talente („Gesamtwaffenschaden“).
- Beispiel: 10.000 Grundschaden, +45 % Waffenschaden, +15 % LMG-Schaden, +20 % Gear-Talent → 10.000 × 1,60 × 1,20 = **19.200**. Weitere +10 % Waffenschaden bringen dann nur +6,25 %, weitere +10 % Gear-Talent dagegen +8,3 %.

### Krit, Kopfschuss, Deckung, Ziel

| Wert | Formel aus den Daten | Hinweis |
| --- | --- | --- |
| Krit-Chance | Summe aller Quellen, Cap `0.6 + CriticalHitChanceOverrideCap` | Cap 60 %, Talente können ihn anheben |
| Krit-Schaden | `0.25 + Waffe + alle Boni + Waffentyp + Talent` | Basis 25 %, alles addiert |
| Kopfschuss | Multiplikator, Cap `WeaponDamageHeadCAP = 10` | maximal 10× |
| Außerhalb Deckung | `1 + alle Boni` | eigener Faktor |
| Schaden an Gesundheit | `1 + DamageDoneToHealthModBonus` | eigener Faktor |
| Schaden an Rüstung (NPC) | `1 + alle Rüstungsschaden-Boni` | eigener Faktor |

### Statuseffekte

Standard-Statuseffekt gegen Gegner (PvE, `NPC_*_Damage_Base`), ein Tick alle 0,5 s (`statuseffecttalentrule_<effekt>`, Regel „(NPC)“, `myFrequency 0.5`):

| Effekt | Schaden pro Tick | Basisdauer |
| --- | --- | --- |
| Brennen | Level-Kurve × 50 × (1 + Statuseffekte) | 5 s |
| Bluten | Level-Kurve × 45 × (1 + Statuseffekte) | 7 s |
| Gift | Level-Kurve × 40, **keine Boni** | 4 s |
| Schock / Blind / Ensnare / Desorientieren | kein Schaden | 3 / 5 / 7 / 7 s |

Gegen Spieler (PvP) gelten `Burn_Damage_Final` usw.: Brennen 40, Bluten 35, Gift 20. Level-Kurve auf Stufe 40 = 1,125^39 × 1,25^5 ≈ 301,65 (`LevelAndTierCurve`), dazu ein Schwierigkeitsfaktor (`BaseGearScalingCurve`, 0,65–2,2).

**Wer nutzt den Standard-Statuseffekt?** Talente und Exotics lösen Statuseffekte über `ApplyStatusEffect` (Talentregel) oder `ApplyStatusEffectNode` (Skillscript) aus. Ohne `myDamageOverride` gilt der Standardschaden. So z. B. Ember Engine (Spontaneous Combustion), Fafnir (Dragon's Breath), Iron Lung (Ardent), Backfire und Ridgeway's Pride (Bluten). Spezialmunition setzt den Wert ausdrücklich, aber identisch (`IncendiaryAmmo_Damage = NPC_Burn_Damage_Base`).

**Skill-Schaden über Zeit** hat eigene Formeln in `player_skill_dictionary.mdict` und Tier-Tabellen in `H\juice\item\skill_tier_<skill>.mskilltier` (`SkillTierUnlock "Tier N"` → `myEffects`):

| Quelle | Grundwert | Formel (vereinfacht) | Tier-Bonus auf Schaden |
| --- | --- | --- | --- |
| Chem-Werfer Brandstifter | 120 | × (1 + Tier) × (1 + Statuseffekte + Skillschaden) × (1 + Gear-Talent-Skillschaden) | Tier 6: +60 % |
| Haftbombe Brand | 120 | × (1 + Tier) × (1 + Skillschaden) × (1 + Statuseffekte) × (1 + Gear-Talent) | Tier 6: +60 %, Tier 7: +100 % |
| Suchermine Luftexplosion | 120 | × (1 + Tier) × (1 + Statuseffekte + Skillschaden) × (1 + Gear-Talent) | Tier 6: +60 %, Tier 7: +100 % |
| Geschütz Flammenwerfer | 80 | × (1 + Tier) × (1 + Statuseffekte + Skillschaden) × (1 + Gear-Talent) | Tier 6: +60 % |
| Hive Stachel, Suchermine Explosiv, Mörser (Bluten) | 45 | × (1 + Statuseffekte + Skillschaden) × (1 + Gear-Talent) | keiner |

**Skill-Direktschaden:** alle `*damage*_Final` in `player_skill_dictionary.mdict`. Muster: Grundwert × Level-Kurve × (1 + Skill-eigene Boni/Tier) × (1 + Skillschaden) × (1 + Explosivschaden, nur Explosionen) × (1 + Gear-Talent-Skillschaden). Geschütz „Überfall“, „Scharfschütze“ und Drohne „Stürmer“ rechnen über Sammel-Boni (`turret_assault_damage_modBonus_Final = (…)×(…)×(…) − 1`), der Extraktor löst sie in Klammern auf. Feuerraten stehen in den Waffendaten der Skills (`R\juice\weapon\npc_weapon_player_turret.mweapon`: 40 Schaden, 750/min; `npc_weapon_player_drone.mweapon`: 25 Schaden, 950/min). Variantennamen: Tier-Datei → `mySkillMod` → `s_mod_*.mitem` → `myUIName`; die Familiennamen der Tier-Tabellen sind uneinheitlich, deshalb ordnet `extract.ps1` Formel → Familie/Tier-Datei fest zu (`$SkillMap`).

**Haftgranate vs. Chem-Werfer/Suchermine (Brennen):** Die Haftgranate multipliziert Skillschaden und Statuseffekte getrennt, die anderen addieren sie in einer Klammer → Haftgranate rechnet bei gleichen Werten mehr (Faktor 1 + S×D / (1 + S + D)).

Ember Engine 4-Teil: 40 % Chance auf Standard-Brennen bei jedem anderen Statuseffekt; war der Auslöser selbst Brennen, erleidet das Ziel +25 % Brandschaden (`skillscript_talent_gearset_spontaneous_combustion_4pc` / `_debuff`).

- Dauer = Basisdauer × (1 + Statuseffekte).
- **Statuseffekte** = Statuseffekt-Attribut + Skill-Effizienz (`AllStatusEffectsModBonus = allskills_efficiency_mod_Bonus`).
- **Skill-Kurve** hängt nur von Level bzw. Gear-Stufe ab, nicht vom Skill-Tier. **Waffenschaden zählt nicht.**
- Beispiel: +30 % Statuseffekte → Brennen macht 1,3× Schaden pro Tick und hält 6,5 s statt 5 s, also insgesamt 1,69×.

### Skills

- Skill-Tier = Summe der Tier-Boni, Cap 6, mit Overcharge 7; im PvP und in normalisierten Modi immer maximal 6.
- Skillschaden hängt an der Skill-Effizienz (`allskills_damage_mod_Bonus = allskills_efficiency_mod_Bonus`).

### Pestilenz

| Wert | PvE | PvP | Survival |
| --- | --- | --- | --- |
| Debuff-Schaden | 100 % Waffenschaden über 10 s | 60 % | 75 % |
| Max. Stapel | 50 | 50 | 50 |
| Übertragung beim Tod | 100 % der Stapel, 25 m | 30 %, 8 m | 100 %, 7 m |

- Pestilenz skaliert mit **Waffenschaden, nicht mit Statuseffekten**. Aktiv ist nur dieses eine Talent („Die Seuche der Outcasts“). „Pestilenz“ (−50 % Heilung) und „Outcast-Belastbarkeit“ (Holster, +20 % Bonusrüstung) stehen noch in den Daten, sind aber nicht mehr mit der Waffe verknüpft.
- Die Berechnung ist hardcoded (Programmcode). Ob Krit oder Kopfschuss mitzählen, verraten die Daten nicht.
- Die Giftwolke (`talentrule_aoe_pestilence_cloud`) ist mit festen 5.000 Giftschaden pro Sekunde hinterlegt; im PvE ist sie laut Spielerfahrung nicht aktiv (Altlast oder PvP-only).

## Update-Anleitung

Nach jedem Patch die Daten neu exportieren, Formeln neu extrahieren und mit dem alten Stand vergleichen.

1. **Spiel und Ubisoft Connect schließen.** Hunter nur bei geschlossenem Spiel benutzen, den Spielordner nie verändern.
2. **Alten Export sichern:** `C:\Users\alex\Downloads\exported_files` umbenennen, z. B. in `exported_files_2026-10-09`.
3. **Hunter starten** (`Downloads\hunter.exe`, v2.2.9; bei Bedarf neue Version von [dtzxporter.com/tools/hunter](https://dtzxporter.com/tools/hunter)).
4. **Einstellungen:** Models, Animations, Images, Materials, Sounds aus; **Load Raw Files an**; Exportordner `C:\Users\alex\Downloads\exported_files`.
5. **Laden:** `D:\UbisoftLibrary\Tom Clancy's The Division 2\hunter\sdf\pc\data\sdf.sdftoc` (die `sdf_streaming`-Dateien werden nicht gebraucht).
6. **Exportieren.** Voller Export ≈ 1,2 Mio. Dateien. Nötig sind nur `hunter\game system data`, `rogue\game system data` und `hunter\localization`.
7. **Optional:** Den Exportordner während des Exports vom Defender-Scan ausnehmen und den Ausschluss danach wieder entfernen.
8. **Daten extrahieren:** im Repo `D:\GitHub\division` ausführen: `powershell -NoProfile -ExecutionPolicy Bypass -File tools\extract.ps1` → schreibt `data\gearsets.json`, `brandsets.json`, `exotics.json`, `formulas.json`, `meta.json` (Laufzeit ca. 1 Minute).
9. **Seite bauen:** `powershell -NoProfile -ExecutionPolicy Bypass -File tools\build.ps1` → `index.html`.
10. **Ansehen:** `powershell -NoProfile -ExecutionPolicy Bypass -File tools\serve.ps1`, dann `http://localhost:8080` öffnen.
11. **Änderungen prüfen:** `git diff --stat data/` zeigt, was sich durch den Patch geändert hat; neue Exotics ohne Community-Daten erscheinen mit Saison-Tag (z. B. Y8S3) statt Datum.
12. **Veröffentlichen:** committen und auf `main` pushen (GitHub Pages).

Build-Datum prüfen: im Header von `sdf.sdftoc` stehen bei Offset 0x24 Jahr, Monat und Tag (aktuell 2026-10-09).

## Wo was liegt

Alle Pfade relativ zu `Downloads\exported_files\raw_files\`.

| Inhalt | Pfad | Umfang |
| --- | --- | --- |
| Attribut-Formeln (Haupt-Wörterbuch) | `rogue\game system data\juice\attribute\dictionary\` | 30 Wörterbücher, 6.986 Attribute |
| Waffenformeln | `…\dictionary\weapon_dictionary.mdict` | Waffenschaden, Krit, Sway |
| Boni / Gear-Stats | `…\dictionary\_bonus_dictionary.mdict` | alle `…ModBonus` |
| Talente | `hunter\game system data\juice\talent\*.mtalent` | 786 |
| Talentregeln | `hunter\game system data\juice\talentrules\*.mtalentrules` | 735 |
| Hardcoded Talente | `hunter\game system data\juice\hardcodedtalent\` | Pestilenz, Eagle Bearer u. a. |
| Brands & Gear-Sets | `hunter\game system data\juice\gearbrand\` | 69 |
| Items (Named, Exotic, Sets) | `hunter\game system data\juice\item\*.mitem` | ~10.200 |
| Exotic-Quellen | `hunter\game system data\rejuice\itemlist_exotics_all.rejuice` | + 80 Exotic-Loot-Tabellen |
| Loot-Tabellen | `hunter\game system data\juice\loot\` | ~2.100 |
| Statuseffekte, Combat | `hunter\game system data\juice\statuseffects\`, `…\combat\` | Einstellungen |
| Schemas (Felddefinitionen) | `hunter\game system data\fruit\` | Klassen und Enums |

Die Spieldateien liegen unter `D:\UbisoftLibrary\Tom Clancy's The Division 2\`; der Ordner `hunter` ist der interne Codename von Division 2, `rogue` der von Division 1.

## Dateiformate

Alle relevanten Dateien sind Klartext im Snowdrop-Datenformat.

| Endung | Was es ist | Beispiel |
| --- | --- | --- |
| `.fruit` | Schema: Klassen, Felder, Enums, Tooltips | `ApplyDamageOrHealing` mit `myDamageOrHealBasedOnSource` |
| `.juice` / `.rejuice` / `.m…` | Daten nach diesem Schema | `.mtalent`, `.mitem`, `.mgearbrand`, `.mloottable` |
| `.mdict` | Attribut-Wörterbuch mit Formeln | `myOriginalFormula`, `mySpecializations` |
| `.decompiled` | von Hunter übersetzte Graphen | bisher nur Animationen |

- **Attribut:** `AttributeDefinition <Name>` mit `myOriginalFormula` und optionalen `Specialization`-Blöcken (`myCondition` + `myFormula`, z. B. Sonderfall für NPCs oder PvP).
- **`…Final`** = fertiger Wert, **`…ModBonus`** = Prozent-Topf (Ausgangswert in der Formel, Gear-Boni kommen dazu), **`…FlatBonus`** = fester Wert.
- **Talent:** `myBonusList` mit `BonusAttributeRef <Name> { myValue }`, dazu `myTalentOverrides` (PvP) und `mySurvivalDungeonTalentOverrides`. Der Tooltip steht in `myToolTipText`, `{0}`, `{1}` … werden der Reihe nach durch die Werte ersetzt.
- **Namen** stehen als `text = \"…\"` in `myUIName` bzw. `myName`.

Das Repo-Skript `tools\extract.ps1` liest alle `.mdict` aus `rogue\…\dictionary` und `hunter\…\dictionary` und schreibt Name, UID, Anzeigename, Formel und Sonderfälle nach `data\formulas.json`; dazu Sets, Brands, Named Items und Exotics (siehe Werkzeuge).

## Schnellreferenz für die KI

Diesen Abschnitt beim nächsten Mal zuerst lesen: Er sagt, wo jede Information liegt und wie die Dateien verknüpft sind, damit nicht der ganze Export durchsucht werden muss.

**Abkürzungen:** `EX` = `C:\Users\alex\Downloads\exported_files\raw_files`, `H` = `EX\hunter\game system data`, `R` = `EX\rogue\game system data`. Spiel: `D:\UbisoftLibrary\Tom Clancy's The Division 2\`. Repo: `D:\GitHub\division` (GitHub `noxickon/division`, GitHub Pages).

### Wo was liegt

| Was | Datei(en) | Wichtige Felder |
| --- | --- | --- |
| Attribut-Formeln | `R\juice\attribute\dictionary\*.mdict` | `AttributeDefinition <Name> < uid=… >`, `myOriginalFormula`, `mySpecializations` |
| Waffen / Status / Boni | `weapon_dictionary.mdict`, `attribute_dictionary.mdict`, `_bonus_dictionary.mdict` (alle in R) | `PhysicalDamageMaxFinal`, `Burn_Damage_Final`, `AllStatusEffectsModBonus` |
| Gear- und Brand-Sets (Boni) | `H\juice\item\gear_brand_set_*.mgearset` (68) | `myUIName`, `myItems`, `myUnlocks` → `GearSetUnlock` mit `myRequiredNumberOfItems` + `myEffects` (`BonusAttributeRef` mit `myAttributeUID`/`myValue` oder `Talent`) + `myEffectsOverrides` (`PvPOverride`) |
| Brand-Namen und Icons | `H\juice\gearbrand\*.mgearbrand` (69) | nur `myName`, `myAbbreviation`, Icon |
| Gear-Set-Talente | `H\juice\talent\talent_gearset_<set>_{chest,backpack,back,5piece,6piece}.mtalent` (96) | `myBonusList`, `myTalentOverrides` (PvP), `myRequirements` |
| Exotic-Talente | `H\juice\talent\talent_exotic_<typ>_mk<N>_{a,b,holstered}.mtalent` (84) | z. B. Pestilenz = `talent_exotic_lmg_mk1_*` |
| Talentregeln (Auslöser, Flächen) | `H\juice\talentrules\*.mtalentrules` (735) | `myRuleList`, `ApplyDamageOrHealing`, Modifikatoren mit `ModificationType` |
| Hardcoded Talente | `H\juice\hardcodedtalent\hardcodedtalentsettings.juice` | Pestilenz, Eagle Bearer, Nemesis, Guerilla Warfare |
| Item → Talent / Attribute | `H\juice\itemgeneration\configs\configs_<kategorie>_code1_data<N>.mitemgenerationconfigs` | `myTalentSlots` → `myPresetTalent`, `myAttributeSlots` |
| Named Items | `H\juice\item\*_named*.mitem`, Links in `H\juice\itemgeneration\configlinks\*_named_config_link.*` (~168) | `myUIName`, `myDescription` (Talenttext im `contextComment`), `ItemTag Named_Brand_<X>` |
| Exotic-Quellen | `H\rejuice\itemlist_exotics_all.rejuice`, Loot-Tabellen `H\juice\loot\ltdrp_*exotic*` | `LootItem "<Typ> - <Name>"`, `myConditions` (z. B. `Has Blueprint`) |
| Statuseffekt-Einstellungen | `H\juice\statuseffects\`, `H\juice\combat\combatsystem.juice` | Spezialmunition → Effekt |
| Schemas (Felddefinitionen) | `H\fruit\<bereich>\*.fruit` | Klassen, Enums, Tooltips der Felder |
| Deutsche Texte | `EX\hunter\localization\packages\german\menus.locpack` | CSV-Zeilen `<GUID>,<n>,<Text>` |

### Verknüpfungen

- **Bonus → Attribut:** `BonusAttributeRef.myAttributeUID` = die `uid` der `AttributeDefinition` in einem `.mdict`. Anzeigename steht dort in `myUIName`. Beispiel: `4F5DDEA25333E552000007BA1FEBF73F` = `BlastDamageMitigationPercentageFlatBonus` („Explosive Resistance“).
- **Text → Deutsch/Englisch:** In `myUIName`/`myToolTipText` steht `guid = #<32 Hex>`. Dieselbe GUID ohne `#` ist der Schlüssel in `EX\hunter\localization\packages\{german,english}\menus.locpack` (CSV `GUID,Version,Text`, mehrzeilige Texte in Anführungszeichen).
- **Tooltip-Platzhalter:** `{0}`, `{1}` … = Einträge von `myBonusList` in ihrer Reihenfolge (geprüft an Pestilenz: `{5}` = 6. Eintrag). Vor einem `%` sind Werte ≤ 10 Anteile (0.2 = 20 %). PvP-Werte: `myTalentOverrides` → `TalentOverride PVP` → `myOverrideBonusList` (gleiche Attribut-UIDs).
- **Item → Talente/Attribute:** Item-Datei (`*.mitem`, in `H\juice\item` **und** `R\juice\item` für ältere Items wie Pestilenz) → `myItemGenerationConfig … = <link>` → `ItemGenerationConfig` mit `myItemGenerationConfigLink = <link>` in `H\juice\itemgeneration\configs\*_code1_data<N>` → `myPresetTalent`, `myPresetAttribute` (= Attribut-UID). Dieselbe Verknüpfung kann in mehreren Config-Dateien stehen; die mit Talenten gilt.
- **Exotic-Talente:** Aktiv ist nur, was die Config verknüpft (heute bei 79 von 82 Exotics genau ein Talent, z. B. `talent_exotic_lmg_mk1_a`). Gleichnamige Nachbar-Talente ohne Verknüpfung (`_b`, `_holstered`, z. B. bei Pestilenz „Pestilenz“ und „Outcast-Belastbarkeit“, insgesamt bei 13 Launch-Exotics) tauchen nur noch in der Icon-Kategorienliste `H\rejuice\itemgenerationsettings.rejuice` auf: Altlasten, auf der Seite nur eingeklappt unter „Herkunft & Quelle“.
- **Sets:** `myItems` im `.mgearset` listet die Teile; Chest- und Rucksack-Talente der Gear-Sets kommen über die Item-Configs der Set-Weste/des Set-Rucksacks.
- **Named Items:** nicht alle stehen in `myItems`. Zuordnung über das Markenkürzel in der Item-ID: `player_gear_back_511_01_named` gehört zur Marke, deren Teile `player_gear_*_511_*` heißen.
- **Saison eines Items:** Item-Tags wie `Y8S3_Exotic_03`.
- **Welches Talent auf welchem Slot würfelt:** `H\juice\itemgeneration\talentlists\talentlist_code1_data<N>.mitemgenerationtalentlists` enthält `TalentListContainer <name> { myTalents { Talent … = <talent_id> } }`. Aktiv sind nur Listen, die eine aktuelle Item-Konfiguration in `myPossibleTalentLists` nennt (auch Vorlagen wie `weapon_item_template_config`): `warlock_chest_talents` (Weste), `warlock_back_talents` (Rucksack), `advanced_weapon_talents` (alle Waffen), `Assault Rifle`, `LMG`, `MMR`, `Pistol`, `Rifle`, `Shotgun`, `shotgun_cycling_only`, `SMG` (je Waffentyp) und `Prototype Augments`. Die Listen `active_*`/`common_*` für Maske, Handschuhe, Holster, Knieschoner sind Altlasten (vor Warlords of New York) und werden nicht mehr benutzt.
- **Bedingung eines Talents:** `myRequirementsText` im Talent (nur wenn `enabled = true`), z. B. „Nur mit Präzisionsgewehren oder Schrotflinten“.
- **Perfekte Talente:** `<talent>_perfect` ist die Named-Item-Version von `<talent>`.
- **Statuseffekt eines Talents:** Talent → `myTalentRules` (Talentregel mit `ApplyStatusEffect { myStatusEffect, myDamageOverride, myChanceToApply }`) oder `mySkillScript` (`EX\hunter\skillscript\<name>.mskillscriptgraph.decompiled`, Knoten `SkillScript:ApplyStatusEffectNode`, Statuseffekt als Konstante `RShared:StatusEffect`). Statuseffekt-UIDs: `R\juice\statuseffects\*.mstatuseffect`. Skillscripts listen oft alle Effekte, auf die sie reagieren; ausgelöst wird der, den der Talenttext nennt.
- **Schaden und Tick-Rate eines Statuseffekts:** `H\juice\talentrules\statuseffecttalentrule_<effekt>.mtalentrules`, Regeln „(Player)“ und „(NPC)“ mit `ApplyDamageOrHealing { myDamageOrHealBasedOnSource, myFrequency }`.
- **Waffenhandling:** in `_bonus_dictionary.mdict` der Grundwert von Wechseltempo, Präzision, Stabilität und Nachladetempo; dazu × 0,25 beim seitlichen Rückstoß (`weapon_dictionary.mdict`).
- **Fertigkeiten-Effizienz:** Grundwert von Skillschaden, Wirkzeit, Skill-Lebensenergie, Reparatur, Fertigkeitentempo und Statuseffekten.

### Fallen

- `gearbrand_set_a.mgearbrand` heißt „Ongoing Directive“, `gear_brand_set_a.mgearset` aber „Golan Gear Ltd“. Immer über Namen und Verknüpfungen gehen, nie über Dateinamen.
- Item-Konfigurationen gibt es mehrfach (`code1_data1` … `code1_data23`); die höchste Nummer ist die aktuelle (der Extraktor nimmt sie automatisch).
- `juice\item` enthält ~10.200 Dateien, größtenteils Optik (`appearance_*`, `*_mtx_*`). Die nicht durchsuchen.
- Nie den ganzen Export durchsuchen: ~480.000 Animationsdateien lassen jede Suche ins Timeout laufen. Nur in `H` und `R` suchen, mit `grep -r` in einem konkreten Unterordner.
- Test- und Alteinträge existieren (z. B. Set „-“, `new gear brand.mgearbrand`); der Extraktor filtert Namen ohne Buchstaben.
- Werte verbesserter Named-Attribute und Höchstwerte fester Exotic-Attribute stehen nur als Kurven in den Daten; sie kommen aus `data\community\*.json`.
- PowerShell 5.1: Variablennamen ignorieren Groß-/Kleinschreibung (`$old` = `$Old`), `@($liste)` in `[ordered]@{}` wirft „Argumenttypen stimmen nicht überein“ (`.ToArray()` nehmen), `ConvertFrom-Json` liefert ein Array als ein Objekt.
- Auf dem PC gibt es weder Node.js noch Python; alle Tools sind PowerShell.
- Die `.ps1`-Dateien müssen **UTF-8 mit BOM** gespeichert sein, sonst liest PowerShell 5.1 sie als ANSI und Umlaute in Texten (z. B. „Mörser“) werden zu Zeichensalat.

### Werkzeuge

- Alles liegt im Repo `D:\GitHub\division` (GitHub `noxickon/division`), Ordner `tools\`:
    - `extract.ps1` – liest den Hunter-Export und schreibt `data\*.json`: `gearsets`, `brandsets`, `exotics`, `talents` (Talente gelber Items mit Slot/Herkunft), `dot` (Schaden-über-Zeit-Quellen mit Grundwert, Formel-Klammern, Tier-Boni, Tick-Rate), `formulas` (alle Attribute), `meta` (Build-Datum). Talente bekommen `applies` (ausgelöste Statuseffekte). Parameter: `-Export <raw_files>`, `-Version <N>`, `-Game <Spielordner>`.
    - `juice.ps1` – Parser für das Snowdrop-Textformat und die `.locpack`-Lokalisierung.
    - `build.ps1` – baut `index.html` aus `template.html` + `data\*.json`.
    - `serve.ps1` – lokaler Server auf `http://localhost:8080`.
- `data\community\*.json` = alte, aus dem Internet gesammelte Daten; liefern nur „seit wann“, Bezugsquelle und Attribut-Höchstwerte.
- Diese Doku liegt als `docs\datamining.md` im Repo.

## Grenzen und Sicherheit

| Weg | Ergebnis |
| --- | --- |
| Arbeitsspeicher des laufenden Spiels auslesen | nicht gemacht: Easy Anti-Cheat erkennt Speicherleser, Bann-Risiko; im RAM stehen Werte, keine Formeln |
| `TheDivision2.exe` dekompilieren | nicht gemacht: geschützt, Umgehen verboten (§ 95a UrhG), Teile laufen auf dem Server |
| Archive selbst entpacken | Inhaltsverzeichnis ist AES-verschlüsselt und signiert (Flags bei 0x60/0x61), Schlüssel nur in der exe |
| Hunter bei geschlossenem Spiel | funktioniert, liefert Klartext-Spieldaten |

- **Hardcoded Talente** (z. B. Pestilenz, Eagle Bearer, Nemesis): Werte stehen in den Daten, die Rechnung im Programmcode.
- **Reihenfolge der Endrechnung** (Krit × Kopfschuss × Rüstung × Deckung) steht nicht als eine Formel in den Daten; die einzelnen Faktoren schon.
- **Altlasten:** Es gibt Test- und Alteinträge (z. B. `new gear brand.mgearbrand`); vor dem Übernehmen prüfen, ob ein Eintrag im Spiel aktiv ist.
- Hunter verstößt gegen Ubisofts Nutzungsbedingungen; Anti-Cheat bekommt den Offline-Export nicht mit. `hunter.exe` ist unsigniert.
- Der Export erzeugt ~1,2 Mio. Dateien: Defender braucht dabei viel CPU. Arbeitsspeicher vorher freimachen (z. B. Minecraft/FTB schließen).

## Entscheidungen für die Division-Page

- **PvE/PvP als Umschalter** bei Gear-Sets, Brand-Sets, Exotics und Named Items. **PvE ist standardmäßig aktiv**, PvP kann man sich ansehen; abweichende Werte sind markiert.
- **Sprache DE/EN als Umschalter**, Deutsch ist Standard; beide Texte kommen offiziell aus dem Spiel.
- Daten kommen aus den Spieldateien statt aus dem Internet.
- Vier Ansichten: **FAQ** (Antworten aus den Daten, z. B. Grundschaden von Brennen/Bluten, Effizienz, Waffenhandling), **Codex** (Sets, Brands, Exotics), **Talente** (nur Talente gelber Items: würfelbare Talente auf Waffen, Westen, Rucksäcken und die Named-Talente der Brand-Sets, jeweils mit Slot/Waffentyp; Gear-Set-, Exotic- und Prototyp-Talente stehen nur im Codex) und **Formeln**. Die obere Leiste mit Ansicht, PvE/PvP und Sprache bleibt beim Scrollen stehen.
- Eine Formel-Ansicht erklärt die Schadensberechnung mit Beispielen und einem Rechner („Was bringt mir +10 %?“); bei jedem Talent und Bonus zeigen Chips, welchen Schadens-Topf es betrifft, mit Link zur Erklärung.

## Offene Punkte

- [ ] Pestilenz: zählen Krit und Kopfschuss im „Waffenschaden“ des Debuffs mit? (nur per Test klärbar)
- [x] Pestilenz-Giftwolke (5.000/s): im PvE nicht aktiv – erledigt
- [ ] Verstärkter Schaden (Amplified): in welchem Topf er landet, steckt in den Talentregeln (`ModificationType` Multiplicative/Additive) – noch auswerten
- [x] Exotics, Gear-Sets, Brands und Named Items für die Division-Page aufbereiten – erledigt (28 Gear-Sets, 37 Brands, 69 Named Items, 82 Exotics)
- [x] Extraktor und Daten-Pipeline ins Repo übernehmen – erledigt (`tools\`)

## Quellen

- [Hunter von DTZxPorter](https://dtzxporter.com/tools/hunter)
- [ZenHAX: Division 2 SDF-Format](https://www.zenhax.com/viewtopic.php@t=9435.html)
- Eigene Auswertung der exportierten Spieldaten, Build 2026-10-09
