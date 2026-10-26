# Schema der Community-Daten (data/community/*.json)

> Diese Dateien wurden frueher von Hand aus Community-Quellen gesammelt. Seit Oktober 2026 kommen die Daten der Seite aus den Spieldateien (`tools/extract.ps1`, siehe `docs/datamining.md`). Aus diesen Dateien werden nur noch "seit wann", Bezugsquellen und Attribut-Hoechstwerte uebernommen.

## Urspruengliches Schema

Target state: The Division 2, Year 8 Season 3 "Red Horizon", patch Y8S3.1 (2026-09-24). PvE values only.
All text in English, using in-game names for sets, items, talents and attributes.

Each output file is a JSON array of entries. One entry:

```jsonc
{
  "id": "aces-and-eights",                 // kebab-case, unique within the file
  "name": "Aces & Eights",                  // exact in-game name
  "kind": "gearset",                        // "gearset" | "brandset" | "exotic"
  "category": null,                         // exotics: "Assault Rifle", "LMG", "Marksman Rifle", "Rifle", "SMG",
                                            // "Shotgun", "Pistol", "Mask", "Chest", "Backpack", "Gloves",
                                            // "Holster", "Kneepads"; gear sets and brand sets: null
  "added": {
    "date": "2019-05",                      // ISO: "YYYY-MM-DD" if the day is known, else "YYYY-MM"
    "update": "Title Update 3",             // TU / Year-Season / DLC that introduced it
    "label": "TU3 · Operation Dark Hours"   // short display label
  },
  "bonuses": [                              // fixed piece bonuses (gear sets: 2 and 3 pieces; brands: 1, 2, 3)
    { "pieces": 2, "stat": "Marksman Rifle Damage", "value": 30, "unit": "%" }
  ],
  "talents": [
    {
      "slot": "4pc",                        // gear sets: "4pc" | "chest" | "backpack"
                                            // exotics: "weapon" | "gear" (use the item's own talent slot)
      "name": "Dead Man's Hand",
      "text": "Full effect in English with all numbers.",
      "stats": ["Weapon Damage", "Headshot Damage"]   // every stat this talent grants, buffs or applies
    }
  ],
  "namedItems": [                           // brand sets only; [] otherwise
    {
      "name": "Keeper",
      "slot": "Backpack",                   // "Mask" | "Chest" | "Backpack" | "Gloves" | "Holster" | "Kneepads"
      "attribute": null,                    // or { "stat": "Armor on Kill", "value": 10, "unit": "%" }
      "talent": { "name": "Perfect Protector", "text": "…", "stats": ["Bonus Armor"] }  // or null
    }
  ],
  "attributes": [                           // exotics only; [] otherwise
    { "stat": "Critical Hit Chance", "value": 21, "unit": "%", "fixed": true }  // fixed:false = rolls randomly
  ],
  "obtain": null,                           // exotics: short "how to get" (e.g. "Raid drop: Dark Hours"), else null
  "confidence": "confirmed",                // "confirmed" (official or ≥2 independent sources agree)
                                            // | "single-source" | "disputed"
  "notes": [],                              // conflicts between sources, recent value changes, open points
  "sources": ["https://…"]
}
```

## Stat vocabulary

Use exactly these names in `stat` and `stats`. Add a new name only when nothing here fits, and list every new name
in your final report.

Offensive: Weapon Damage, Critical Hit Chance, Critical Hit Damage, Headshot Damage, Weapon Handling, Rate of Fire,
Magazine Size, Reload Speed, Ammo Capacity, Accuracy, Stability, Optimal Range, Damage to Armor, Damage to Health,
Damage to Targets out of Cover, Assault Rifle Damage, LMG Damage, Marksman Rifle Damage, Rifle Damage, SMG Damage,
Shotgun Damage, Pistol Damage, Signature Weapon Damage, Melee Damage, Explosive Damage, Damage Amplification

Defensive: Total Armor, Armor Regeneration, Armor on Kill, Bonus Armor, Armor Repair, Health, Health on Kill,
Damage Resistance, Hazard Protection, Explosive Resistance, Protection from Elites, Increased Threat,
Reduced Threat, Disrupt Resistance, Pulse Resistance

Skill: Skill Damage, Skill Haste, Skill Duration, Skill Cooldown, Repair Skills, Skill Health, Skill Efficiency,
Skill Tier, Overcharge, Shield Health

Status effects: Status Effects, Burn, Bleed, Shock, Blind, Disorient, Ensnare, Confuse, Pulse, Disrupt,
Burn Damage, Burn Duration, Bleed Damage

Rule for `stats` on talents: tag what the player can get or apply through the talent. A talent that applies Bleed
gets "Bleed" and "Status Effects"; one that scales with or triggers on status effects gets "Status Effects".
