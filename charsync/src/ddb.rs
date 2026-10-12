//! Converts D&D Beyond's (unofficial) character-service JSON into charsheet's format.
//!
//! The feed is undocumented, so every lookup is defensive: missing or
//! unexpected fields fall back to sane defaults instead of failing.

use crate::model::{Abilities, Action, Character, Feature, proficiency};
use anyhow::{Context, Result, bail};
use serde_json::Value;
use std::collections::{BTreeMap, HashSet};

const ABILITIES: [&str; 6] = ["str", "dex", "con", "int", "wis", "cha"];
const ABILITY_NAMES: [&str; 6] = [
    "strength",
    "dexterity",
    "constitution",
    "intelligence",
    "wisdom",
    "charisma",
];

const SKILLS: [(&str, &str); 18] = [
    ("acrobatics", "acrobatics"),
    ("animal-handling", "animalHandling"),
    ("arcana", "arcana"),
    ("athletics", "athletics"),
    ("deception", "deception"),
    ("history", "history"),
    ("insight", "insight"),
    ("intimidation", "intimidation"),
    ("investigation", "investigation"),
    ("medicine", "medicine"),
    ("nature", "nature"),
    ("perception", "perception"),
    ("performance", "performance"),
    ("persuasion", "persuasion"),
    ("religion", "religion"),
    ("sleight-of-hand", "sleightOfHand"),
    ("stealth", "stealth"),
    ("survival", "survival"),
];

/// Full-caster slot table by caster level (multiclass rules).
const FULL_CASTER_SLOTS: [[i32; 9]; 20] = [
    [2, 0, 0, 0, 0, 0, 0, 0, 0],
    [3, 0, 0, 0, 0, 0, 0, 0, 0],
    [4, 2, 0, 0, 0, 0, 0, 0, 0],
    [4, 3, 0, 0, 0, 0, 0, 0, 0],
    [4, 3, 2, 0, 0, 0, 0, 0, 0],
    [4, 3, 3, 0, 0, 0, 0, 0, 0],
    [4, 3, 3, 1, 0, 0, 0, 0, 0],
    [4, 3, 3, 2, 0, 0, 0, 0, 0],
    [4, 3, 3, 3, 1, 0, 0, 0, 0],
    [4, 3, 3, 3, 2, 0, 0, 0, 0],
    [4, 3, 3, 3, 2, 1, 0, 0, 0],
    [4, 3, 3, 3, 2, 1, 0, 0, 0],
    [4, 3, 3, 3, 2, 1, 1, 0, 0],
    [4, 3, 3, 3, 2, 1, 1, 0, 0],
    [4, 3, 3, 3, 2, 1, 1, 1, 0],
    [4, 3, 3, 3, 2, 1, 1, 1, 0],
    [4, 3, 3, 3, 2, 1, 1, 1, 1],
    [4, 3, 3, 3, 3, 1, 1, 1, 1],
    [4, 3, 3, 3, 3, 2, 1, 1, 1],
    [4, 3, 3, 3, 3, 2, 2, 1, 1],
];

/// Warlock pact magic: (slot count, slot level) by warlock level.
const PACT_SLOTS: [(i32, usize); 20] = [
    (1, 1),
    (2, 1),
    (2, 2),
    (2, 2),
    (2, 3),
    (2, 3),
    (2, 4),
    (2, 4),
    (2, 5),
    (2, 5),
    (3, 5),
    (3, 5),
    (3, 5),
    (3, 5),
    (3, 5),
    (3, 5),
    (4, 5),
    (4, 5),
    (4, 5),
    (4, 5),
];

/// Accepts a numeric id or any dndbeyond.com character URL.
pub fn parse_character_id(input: &str) -> Result<u64> {
    let s = input.trim().trim_end_matches('/');
    if let Ok(id) = s.parse() {
        return Ok(id);
    }
    if let Some(pos) = s.find("/characters/") {
        let digits: String = s[pos + 12..]
            .chars()
            .take_while(|c| c.is_ascii_digit())
            .collect();
        if let Ok(id) = digits.parse() {
            return Ok(id);
        }
    }
    bail!(
        "couldn't find a character id in {input:?} (expected e.g. 27935516 or https://www.dndbeyond.com/characters/27935516)"
    )
}

pub fn fetch(id: u64) -> Result<Value> {
    let url = format!("https://character-service.dndbeyond.com/character/v5/character/{id}");
    let mut resp = match ureq::get(&url)
        .header(
            "User-Agent",
            concat!("charsync/", env!("CARGO_PKG_VERSION")),
        )
        .header("Accept", "application/json")
        .call()
    {
        Ok(r) => r,
        Err(ureq::Error::StatusCode(403)) | Err(ureq::Error::StatusCode(401)) => bail!(
            "character {id} is private. In D&D Beyond open the character > Manage > Character Settings and set Privacy to Public"
        ),
        Err(ureq::Error::StatusCode(404)) => bail!("character {id} not found"),
        Err(e) => return Err(e).context("fetching from D&D Beyond"),
    };
    let text = resp
        .body_mut()
        .read_to_string()
        .context("reading D&D Beyond response")?;
    serde_json::from_str(&text).context("D&D Beyond returned invalid JSON")
}

/// Returns the character object whether given the full response or just `data`.
pub fn character_data(v: &Value) -> Result<&Value> {
    let d = if v.get("data").is_some_and(Value::is_object) {
        &v["data"]
    } else {
        v
    };
    if d.get("stats").is_none() || d.get("classes").is_none() {
        if let Some(msg) = v.get("message").and_then(Value::as_str) {
            bail!("D&D Beyond: {msg}");
        }
        bail!("this doesn't look like a D&D Beyond character");
    }
    Ok(d)
}

// ---------------------------------------------------------------- helpers

fn arr(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}

fn int(v: &Value) -> Option<i32> {
    v.as_i64()
        .map(|n| n as i32)
        .or_else(|| v.as_f64().map(|f| f as i32))
}

fn text(v: &Value) -> Option<&str> {
    v.as_str().filter(|s| !s.trim().is_empty())
}

fn ability_by_id(id: i32) -> Option<&'static str> {
    ABILITIES.get((id - 1) as usize).copied()
}

/// Folds typographic punctuation to ASCII; the Playdate fonts are ASCII-only.
pub fn ascii(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\u{2018}' | '\u{2019}' | '\u{02BC}' => out.push('\''),
            '\u{201C}' | '\u{201D}' => out.push('"'),
            '\u{2013}' | '\u{2014}' | '\u{2212}' => out.push('-'),
            '\u{2026}' => out.push_str("..."),
            '\u{00D7}' => out.push('x'),
            c if c.is_ascii() && !c.is_ascii_control() => out.push(c),
            c if c.is_whitespace() => out.push(' '),
            c => {
                // strip accents for the common Latin-1 range, drop anything else
                let base = match c {
                    'à'..='å' => 'a',
                    'À'..='Å' => 'A',
                    'è'..='ë' => 'e',
                    'È'..='Ë' => 'E',
                    'ì'..='ï' => 'i',
                    'Ì'..='Ï' => 'I',
                    'ò'..='ö' => 'o',
                    'Ò'..='Ö' => 'O',
                    'ù'..='ü' => 'u',
                    'Ù'..='Ü' => 'U',
                    'ñ' => 'n',
                    'Ñ' => 'N',
                    'ç' => 'c',
                    'Ç' => 'C',
                    'ý' | 'ÿ' => 'y',
                    _ => continue,
                };
                out.push(base);
            }
        }
    }
    out.trim().to_string()
}

/// Plain-text rule summary from a D&D Beyond snippet or HTML description.
fn rule_text(v: &Value) -> Option<String> {
    const MAX: usize = 400;
    let src = text(&v["snippet"]).or_else(|| text(&v["description"]))?;
    let mut plain = String::with_capacity(src.len());
    let (mut in_tag, mut braces) = (false, 0);
    let mut chars = src.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '<' => in_tag = true,
            '>' if in_tag => {
                in_tag = false;
                plain.push(' ')
            }
            _ if in_tag => {}
            // DDB templates like {{scalevalue}} can't be evaluated here
            '{' if chars.peek() == Some(&'{') => {
                chars.next();
                braces += 1;
                if braces == 1 {
                    plain.push('X')
                }
            }
            '}' if braces > 0 && chars.peek() == Some(&'}') => {
                chars.next();
                braces -= 1
            }
            _ if braces > 0 => {}
            _ => plain.push(c),
        }
    }
    let plain = plain
        .replace("&nbsp;", " ")
        .replace("&rsquo;", "'")
        .replace("&lsquo;", "'")
        .replace("&ldquo;", "\"")
        .replace("&rdquo;", "\"")
        .replace("&mdash;", "-")
        .replace("&ndash;", "-")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&");
    let words: Vec<&str> = plain.split_whitespace().collect();
    let mut out = ascii(&words.join(" "));
    if out.len() > MAX {
        let cut = out[..MAX].rfind(' ').unwrap_or(MAX);
        out.truncate(cut);
        out.push_str("...");
    }
    (!out.is_empty()).then_some(out)
}

fn camel_id(name: &str) -> String {
    let mut out = String::new();
    for (i, word) in name
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|w| !w.is_empty())
        .enumerate()
    {
        let lower = word.to_ascii_lowercase();
        if i == 0 {
            out.push_str(&lower);
        } else {
            let mut cs = lower.chars();
            if let Some(f) = cs.next() {
                out.push(f.to_ascii_uppercase());
                out.extend(cs);
            }
        }
    }
    if out.is_empty() {
        "feature".into()
    } else {
        out
    }
}

fn slug(s: &str) -> String {
    s.to_ascii_lowercase()
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

/// "1d8" + 3 -> "1d8+3"; omits a zero bonus.
fn dice_plus(dice: &str, bonus: i32) -> String {
    match bonus {
        0 => dice.to_string(),
        b if b > 0 => format!("{dice}+{b}"),
        b => format!("{dice}{b}"),
    }
}

struct Mod<'a> {
    kind: &'a str,
    sub: &'a str,
    value: Option<i32>,
    stat: Option<i32>,
}

// ---------------------------------------------------------------- converter

struct Ctx<'a> {
    d: &'a Value,
    mods: Vec<Mod<'a>>,
    abilities: Abilities,
    level: i32,
    pb: i32,
}

impl<'a> Ctx<'a> {
    fn new(d: &'a Value) -> Self {
        // item modifiers only count for equipped (and attuned, if required) items
        let equipped: HashSet<i64> = arr(&d["inventory"])
            .iter()
            .filter(|i| i["equipped"].as_bool() == Some(true))
            .filter(|i| {
                i["definition"]["canAttune"].as_bool() != Some(true)
                    || i["isAttuned"].as_bool() == Some(true)
            })
            .filter_map(|i| i["definition"]["id"].as_i64())
            .collect();

        let mut mods = Vec::new();
        if let Some(groups) = d["modifiers"].as_object() {
            for (source, list) in groups {
                for m in arr(list) {
                    let component = m["componentId"].as_i64();
                    if source == "item" && !component.is_some_and(|c| equipped.contains(&c)) {
                        continue;
                    }
                    mods.push(Mod {
                        kind: m["type"].as_str().unwrap_or(""),
                        sub: m["subType"].as_str().unwrap_or(""),
                        value: int(&m["value"]).or_else(|| int(&m["fixedValue"])),
                        stat: int(&m["statId"]),
                    });
                }
            }
        }

        let level = arr(&d["classes"])
            .iter()
            .filter_map(|c| int(&c["level"]))
            .sum::<i32>()
            .max(1);
        let mut ctx = Ctx {
            d,
            mods,
            abilities: Abilities::default(),
            level,
            pb: proficiency(level),
        };
        ctx.abilities = ctx.compute_abilities();
        ctx
    }

    fn sum(&self, kind: &str, sub: &str) -> i32 {
        self.mods
            .iter()
            .filter(|m| m.kind == kind && m.sub == sub)
            .filter_map(|m| m.value)
            .sum()
    }

    fn has(&self, kind: &str, sub: &str) -> bool {
        self.mods.iter().any(|m| m.kind == kind && m.sub == sub)
    }

    fn stat_entry(&self, field: &str, id: i32) -> Option<i32> {
        arr(&self.d[field])
            .iter()
            .find(|s| int(&s["id"]) == Some(id))
            .and_then(|s| int(&s["value"]))
    }

    fn compute_abilities(&self) -> Abilities {
        let mut out = Abilities::default();
        for (i, ab) in ABILITIES.iter().enumerate() {
            let id = i as i32 + 1;
            let sub = format!("{}-score", ABILITY_NAMES[i]);
            let mut score = self.stat_entry("stats", id).unwrap_or(10)
                + self.stat_entry("bonusStats", id).unwrap_or(0)
                + self.sum("bonus", &sub);
            // items like Gauntlets of Ogre Power set a minimum score
            for m in self.mods.iter().filter(|m| m.kind == "set" && m.sub == sub) {
                score = score.max(m.value.unwrap_or(0));
            }
            if let Some(o) = self.stat_entry("overrideStats", id) {
                score = o;
            }
            out.set(ab, score);
        }
        out
    }

    fn classes(&self) -> &'a [Value] {
        arr(&self.d["classes"])
    }

    /// Feature names unlocked so far (class features + racial traits + feats).
    fn feature_names(&self) -> Vec<String> {
        let mut names = Vec::new();
        for c in self.classes() {
            let lvl = int(&c["level"]).unwrap_or(0);
            for f in arr(&c["classFeatures"]) {
                let def = &f["definition"];
                if int(&def["requiredLevel"]).unwrap_or(1) <= lvl
                    && let Some(n) = text(&def["name"])
                {
                    names.push(n.to_string());
                }
            }
        }
        for t in arr(&self.d["race"]["racialTraits"]) {
            if let Some(n) = text(&t["definition"]["name"]) {
                names.push(n.to_string());
            }
        }
        for f in arr(&self.d["feats"]) {
            if let Some(n) = text(&f["definition"]["name"]) {
                names.push(n.to_string());
            }
        }
        names
    }

    fn hp(&self) -> i32 {
        let d = self.d;
        if let Some(o) = int(&d["overrideHitPoints"]) {
            return o.max(1);
        }
        let base = int(&d["baseHitPoints"]).unwrap_or(0);
        let con = self.abilities.modifier("con") * self.level;
        let per_level = self.sum("bonus", "hit-points-per-level") * self.level;
        (base + con + per_level + int(&d["bonusHitPoints"]).unwrap_or(0)).max(1)
    }

    fn speed(&self) -> i32 {
        let race = int(&self.d["race"]["weightSpeeds"]["normal"]["walk"]).unwrap_or(30);
        let set = self
            .mods
            .iter()
            .filter(|m| m.kind == "set" && m.sub == "innate-speed-walking")
            .filter_map(|m| m.value)
            .max()
            .unwrap_or(0);
        race.max(set)
            + self.sum("bonus", "speed")
            + self.sum("bonus", "speed-walking")
            + self.sum("bonus", "unarmored-movement")
    }

    fn ac(&self) -> i32 {
        let dex = self.abilities.modifier("dex");
        let mut body: Option<i32> = None;
        let mut shield = 0;
        for i in arr(&self.d["inventory"])
            .iter()
            .filter(|i| i["equipped"].as_bool() == Some(true))
        {
            let def = &i["definition"];
            let base = int(&def["armorClass"]).unwrap_or(0);
            match int(&def["armorTypeId"]) {
                Some(1) => body = Some(body.unwrap_or(0).max(base + dex)),
                Some(2) => body = Some(body.unwrap_or(0).max(base + dex.min(2))),
                Some(3) => body = Some(body.unwrap_or(0).max(base)),
                Some(4) => shield = shield.max(base),
                _ => {}
            }
        }
        let body = body.unwrap_or_else(|| {
            // Unarmored Defense (barbarian CON, monk WIS) or a fixed base (Draconic Resilience)
            let mut best = 10 + dex;
            for m in self
                .mods
                .iter()
                .filter(|m| m.kind == "set" && m.sub == "unarmored-armor-class")
            {
                let stat = m
                    .stat
                    .and_then(ability_by_id)
                    .map(|a| self.abilities.modifier(a))
                    .unwrap_or(0);
                best = best.max(10 + dex + stat + m.value.unwrap_or(0));
            }
            best
        });
        body + shield + self.sum("bonus", "armor-class")
    }

    fn saves(&self) -> Vec<String> {
        ABILITIES
            .iter()
            .zip(ABILITY_NAMES)
            .filter(|(_, name)| self.has("proficiency", &format!("{name}-saving-throws")))
            .map(|(ab, _)| ab.to_string())
            .collect()
    }

    fn skills(&self) -> BTreeMap<String, u8> {
        let mut out = BTreeMap::new();
        for (sub, key) in SKILLS {
            if self.has("expertise", sub) {
                out.insert(key.to_string(), 2);
            } else if self.has("proficiency", sub) {
                out.insert(key.to_string(), 1);
            }
        }
        out
    }

    fn class_label(&self) -> String {
        let names: Vec<String> = self
            .classes()
            .iter()
            .filter_map(|c| text(&c["definition"]["name"]).map(ascii))
            .collect();
        if names.is_empty() {
            "Adventurer".into()
        } else {
            names.join("/")
        }
    }

    fn primary_class(&self) -> Option<&'a Value> {
        let cs = self.classes();
        cs.iter()
            .find(|c| c["isStartingClass"].as_bool() == Some(true))
            .or(cs.first())
    }

    fn class_ability(&self, class: &Value) -> Option<&'static str> {
        int(&class["definition"]["spellCastingAbilityId"])
            .or_else(|| int(&class["subclassDefinition"]["spellCastingAbilityId"]))
            .and_then(ability_by_id)
    }

    fn spell_ability(&self) -> Option<&'static str> {
        let primary = self.primary_class().and_then(|c| self.class_ability(c));
        primary.or_else(|| self.classes().iter().find_map(|c| self.class_ability(c)))
    }

    fn slots(&self) -> Vec<i32> {
        let mut casters = Vec::new();
        let mut pact: Option<(i32, usize)> = None;
        for c in self.classes() {
            let lvl = int(&c["level"]).unwrap_or(0);
            let name = c["definition"]["name"].as_str().unwrap_or("");
            if name == "Warlock" {
                pact = PACT_SLOTS.get((lvl - 1).clamp(0, 19) as usize).copied();
                continue;
            }
            for def in [&c["definition"], &c["subclassDefinition"]] {
                let rules = &def["spellRules"];
                let table = arr(&rules["levelSpellSlots"]);
                let row: Vec<i32> = table
                    .get(lvl as usize)
                    .map(|r| arr(r).iter().filter_map(int).collect())
                    .unwrap_or_default();
                if row.iter().any(|&n| n > 0)
                    || (def["canCastSpells"].as_bool() == Some(true) && !table.is_empty())
                {
                    let divisor = int(&rules["multiClassSpellSlotDivisor"])
                        .unwrap_or(1)
                        .max(1);
                    let rounds_up = rules["multiClassSpellSlotRounding"].as_i64() == Some(2);
                    casters.push((lvl, divisor, rounds_up, row));
                    break;
                }
            }
        }

        let mut slots: Vec<i32> = match casters.len() {
            0 => Vec::new(),
            1 => casters.remove(0).3,
            _ => {
                let caster_level: i32 = casters
                    .iter()
                    .map(|(l, div, up, _)| if *up { (l + div - 1) / div } else { l / div })
                    .sum();
                FULL_CASTER_SLOTS
                    .get((caster_level - 1).max(-1) as usize)
                    .map(|r| r.to_vec())
                    .unwrap_or_default()
            }
        };
        if let Some((count, level)) = pact {
            if slots.len() < level {
                slots.resize(level, 0);
            }
            slots[level - 1] += count;
        }
        while slots.last() == Some(&0) {
            slots.pop();
        }
        slots
    }

    // ------------------------------------------------------------ actions

    fn weapons(&self, rows: &mut Vec<Action>) {
        let mut seen = HashSet::new();
        let melee_bonus =
            self.sum("bonus", "melee-weapon-attacks") + self.sum("bonus", "weapon-attacks");
        let ranged_bonus =
            self.sum("bonus", "ranged-weapon-attacks") + self.sum("bonus", "weapon-attacks");
        for i in arr(&self.d["inventory"])
            .iter()
            .filter(|i| i["equipped"].as_bool() == Some(true))
        {
            let def = &i["definition"];
            if def["filterType"].as_str() != Some("Weapon") {
                continue;
            }
            let Some(dice) = text(&def["damage"]["diceString"]) else {
                continue;
            };
            let name = ascii(text(&def["name"]).unwrap_or("Weapon"));
            if !seen.insert(name.clone()) {
                continue;
            }
            let props: Vec<String> = arr(&def["properties"])
                .iter()
                .filter_map(|p| p["name"].as_str().map(str::to_ascii_lowercase))
                .collect();
            let has = |p: &str| props.iter().any(|x| x == p);
            let ranged = int(&def["attackType"]) == Some(2);

            let (str_m, dex_m) = (
                self.abilities.modifier("str"),
                self.abilities.modifier("dex"),
            );
            let ab_mod = if has("finesse") {
                str_m.max(dex_m)
            } else if ranged {
                dex_m
            } else {
                str_m
            };

            let base_type = text(&def["type"]).map(slug).unwrap_or_default();
            let category = match int(&def["categoryId"]) {
                Some(1) => "simple-weapons",
                Some(2) => "martial-weapons",
                _ => "",
            };
            let proficient = self.has("proficiency", &base_type)
                || (!category.is_empty() && self.has("proficiency", category))
                || self.has("proficiency", &slug(&name));

            let magic: i32 = arr(&def["grantedModifiers"])
                .iter()
                .filter(|m| {
                    m["type"].as_str() == Some("bonus") && m["subType"].as_str() == Some("magic")
                })
                .filter_map(|m| int(&m["value"]).or_else(|| int(&m["fixedValue"])))
                .sum();

            let hit = ab_mod
                + if proficient { self.pb } else { 0 }
                + magic
                + if ranged { ranged_bonus } else { melee_bonus };
            let note = if ranged || has("thrown") {
                match (int(&def["range"]), int(&def["longRange"])) {
                    (Some(r), Some(l)) if l > r => Some(format!("{r}/{l}")),
                    (Some(r), _) if r > 5 => Some(format!("{r} ft")),
                    _ => None,
                }
            } else {
                ["finesse", "reach", "versatile", "heavy"]
                    .iter()
                    .find(|p| has(p))
                    .map(|p| p.to_string())
            };
            rows.push(Action {
                name: Some(name),
                atk: Some(
                    if ranged || (has("finesse") && dex_m > str_m) {
                        "dex"
                    } else {
                        "str"
                    }
                    .into(),
                ),
                hit: Some(hit),
                dmg: Some(dice_plus(dice, ab_mod + magic)),
                kind: text(&def["damageType"]).map(|t| t.to_ascii_lowercase()),
                note,
                ..Default::default()
            });
        }
    }

    /// Limited-use actions from race/class/feats/items -> features (+ rollable rows).
    fn limited_actions(&self, features: &mut Vec<Feature>, rows: &mut Vec<Action>) {
        let mut ids = HashSet::new();
        let Some(groups) = self.d["actions"].as_object() else {
            return;
        };
        for list in groups.values() {
            for a in arr(list) {
                let Some(name) = text(&a["name"]).map(ascii) else {
                    continue;
                };
                let lu = &a["limitedUse"];
                let mut uses = None;
                if lu.is_object() {
                    let mut max = int(&lu["maxUses"]).unwrap_or(0);
                    if lu["useProficiencyBonus"].as_bool() == Some(true) {
                        max += self.pb;
                    }
                    if let Some(ab) = int(&lu["statModifierUsesId"]).and_then(ability_by_id) {
                        max += self.abilities.modifier(ab).max(1);
                    }
                    if max > 0 {
                        let id = camel_id(&name);
                        if ids.insert(id.clone()) {
                            let reset = if int(&lu["resetType"]) == Some(1) {
                                "short"
                            } else {
                                "long"
                            };
                            features.push(Feature {
                                id: id.clone(),
                                name: name.clone(),
                                max,
                                reset: reset.into(),
                                rule: rule_text(a),
                            });
                        }
                        uses = Some(id);
                    }
                }

                let Some(dice) = text(&a["dice"]["diceString"]) else {
                    continue;
                };
                let stat_bonus = int(&a["abilityModifierStatId"])
                    .and_then(ability_by_id)
                    .map(|ab| self.abilities.modifier(ab))
                    .unwrap_or(0);
                let expr = dice_plus(dice, stat_bonus + int(&a["value"]).unwrap_or(0));
                let snippet = a["snippet"].as_str().unwrap_or("").to_ascii_lowercase();
                let healing = snippet.contains("regain") && snippet.contains("hit point");
                let note = uses.as_ref().map(|_| {
                    let f = features.iter().find(|f| Some(&f.id) == uses.as_ref());
                    f.map(|f| format!("{}/{}", f.max, if f.reset == "short" { "SR" } else { "LR" }))
                        .unwrap_or_default()
                });
                let mut row = Action {
                    name: Some(name),
                    note,
                    uses,
                    rule: rule_text(a),
                    ..Default::default()
                };
                if healing {
                    row.heal = Some(expr);
                    row.self_heal = Some(true);
                } else if let Some(save) = int(&a["saveStatId"]).and_then(ability_by_id) {
                    row.save = Some(save.into());
                    row.dmg = Some(expr);
                    row.dc = int(&a["fixedSaveDc"]).or_else(|| {
                        let ab = int(&a["abilityModifierStatId"])
                            .and_then(ability_by_id)
                            .unwrap_or("con");
                        Some(8 + self.pb + self.abilities.modifier(ab))
                    });
                } else {
                    row.dmg = Some(expr);
                    row.critable = Some(true);
                    row.kind = Some("extra".into());
                }
                rows.push(row);
            }
        }
    }

    /// (spells, class ability, is prepared caster list) for each spell source.
    fn spell_sources(&self) -> Vec<(Vec<&'a Value>, Option<&'static str>)> {
        let mut out = Vec::new();
        for cs in arr(&self.d["classSpells"]) {
            let class = self
                .classes()
                .iter()
                .find(|c| c["id"] == cs["characterClassId"]);
            let ability = class.and_then(|c| self.class_ability(c));
            let spells: Vec<&Value> = arr(&cs["spells"]).iter().collect();
            // prepared casters list their whole spellbook; keep only what's ready
            let any_prepared = spells.iter().any(|s| s["prepared"].as_bool() == Some(true));
            let ready = spells
                .into_iter()
                .filter(|s| {
                    !any_prepared
                        || s["prepared"].as_bool() == Some(true)
                        || s["alwaysPrepared"].as_bool() == Some(true)
                        || int(&s["definition"]["level"]) == Some(0)
                })
                .collect();
            out.push((ready, ability));
        }
        if let Some(groups) = self.d["spells"].as_object() {
            for list in groups.values() {
                out.push((arr(list).iter().collect(), None));
            }
        }
        out
    }

    fn spells(
        &self,
        features: &mut Vec<Feature>,
        cantrips: &mut Vec<Action>,
        leveled: &mut Vec<Action>,
    ) {
        let spell_atk_bonus = self.sum("bonus", "spell-attacks");
        let spell_dc_bonus = self.sum("bonus", "spell-save-dc");
        let mut seen = HashSet::new();
        for (spells, class_ability) in self.spell_sources() {
            for s in spells {
                let def = &s["definition"];
                let Some(name) = text(&def["name"]).map(ascii) else {
                    continue;
                };
                if !seen.insert(name.clone()) {
                    continue;
                }
                let level = int(&def["level"]).unwrap_or(0);
                let ability = int(&s["spellCastingAbilityId"])
                    .and_then(ability_by_id)
                    .or(class_ability)
                    .or_else(|| self.spell_ability())
                    .unwrap_or("int");
                let ab_mod = self.abilities.modifier(ability);

                let mut damage = Vec::new();
                let mut dmg_type = None;
                let mut heal = None;
                for m in arr(&def["modifiers"]) {
                    let die = self.scaled_die(m, level);
                    let primary = if m["usePrimaryStat"].as_bool() == Some(true) {
                        ab_mod
                    } else {
                        0
                    };
                    match m["type"].as_str() {
                        Some("damage") => {
                            if let Some(d) = die {
                                damage.push(dice_plus(&d, primary));
                                dmg_type =
                                    dmg_type.or_else(|| text(&m["subType"]).map(str::to_string));
                            }
                        }
                        Some("bonus") if m["subType"].as_str() == Some("hit-points") => {
                            heal = die.map(|d| dice_plus(&d, primary));
                        }
                        _ => {}
                    }
                }
                if damage.is_empty() && heal.is_none() {
                    continue; // utility spell: nothing to roll
                }

                let range = &def["range"];
                let note = if level == 0 {
                    match (range["origin"].as_str(), int(&range["rangeValue"])) {
                        (_, Some(r)) if r > 0 => Some(format!("{r} ft")),
                        (Some(o), _) => Some(ascii(o).to_ascii_lowercase()),
                        _ => None,
                    }
                } else {
                    Some(format!("L{level}"))
                };

                // innate / item spells with their own uses don't spend slots
                let lu = &s["limitedUse"];
                let mut uses = None;
                if level > 0 && lu.is_object() && int(&lu["maxUses"]).unwrap_or(0) > 0 {
                    let id = camel_id(&name);
                    let reset = if int(&lu["resetType"]) == Some(1) {
                        "short"
                    } else {
                        "long"
                    };
                    features.push(Feature {
                        id: id.clone(),
                        name: name.clone(),
                        max: int(&lu["maxUses"]).unwrap_or(1),
                        reset: reset.into(),
                        rule: None,
                    });
                    uses = Some(id);
                }
                let slot = if level > 0 && uses.is_none() {
                    Some(level)
                } else {
                    None
                };

                let mut row = Action {
                    name: Some(name),
                    note,
                    slot,
                    uses,
                    rule: rule_text(def),
                    ..Default::default()
                };
                if let Some(h) = heal.filter(|_| damage.is_empty()) {
                    row.heal = Some(h);
                } else {
                    row.dmg = Some(damage.join("+"));
                    row.kind = dmg_type.map(|t| t.to_ascii_lowercase());
                    if def["requiresAttackRoll"].as_bool() == Some(true)
                        || int(&def["attackType"]).is_some()
                    {
                        row.atk = Some("spell".into());
                        row.hit = Some(ab_mod + self.pb + spell_atk_bonus);
                    } else if let Some(save) = int(&def["saveDcAbilityId"])
                        .and_then(ability_by_id)
                        .filter(|_| def["requiresSavingThrow"].as_bool() != Some(false))
                    {
                        row.save = Some(save.into());
                        row.dc = Some(
                            int(&s["overrideSaveDc"])
                                .unwrap_or(8 + self.pb + ab_mod + spell_dc_bonus),
                        );
                    } else {
                        row.auto = Some(true);
                    }
                }
                if level == 0 {
                    cantrips.push(row)
                } else {
                    leveled.push(row)
                }
            }
        }
        leveled.sort_by_key(|a| a.slot.unwrap_or(0));
    }

    /// The spell's die, scaled for cantrips by character level.
    fn scaled_die(&self, m: &Value, spell_level: i32) -> Option<String> {
        let fixed = int(&m["die"]["fixedValue"]).unwrap_or(0);
        let mut die = text(&m["die"]["diceString"])
            .map(|d| dice_plus(d, fixed))
            .or_else(|| (fixed != 0).then(|| fixed.to_string()));
        if spell_level == 0 {
            let mut best = 0;
            for h in arr(&m["atHigherLevels"]["higherLevelDefinitions"]) {
                let lvl = int(&h["level"]).unwrap_or(99);
                if lvl <= self.level
                    && lvl >= best
                    && let Some(d) = text(&h["dice"]["diceString"])
                {
                    die = Some(dice_plus(d, fixed));
                    best = lvl;
                }
            }
        }
        die
    }
}

pub fn convert(raw: &Value) -> Result<Character> {
    let d = character_data(raw)?;
    let ctx = Ctx::new(d);
    let id = d["id"].as_i64().context("character has no id")?;

    let feature_names = ctx.feature_names();
    let has_feature = |n: &str| feature_names.iter().any(|f| f.eq_ignore_ascii_case(n));
    let crit_range = if has_feature("Superior Critical") {
        18
    } else if has_feature("Improved Critical") {
        19
    } else {
        20
    };

    let mut features = Vec::new();
    let mut weapons = Vec::new();
    let mut feats = Vec::new();
    let mut cantrips = Vec::new();
    let mut spells = Vec::new();
    ctx.weapons(&mut weapons);
    ctx.limited_actions(&mut features, &mut feats);
    ctx.spells(&mut features, &mut cantrips, &mut spells);

    let mut actions = Vec::new();
    for (title, rows) in [
        ("Weapons", weapons),
        ("Features", feats),
        ("Cantrips", cantrips),
        ("Spells", spells),
    ] {
        if !rows.is_empty() {
            actions.push(Action::section(title));
            actions.extend(rows);
        }
    }
    if actions.is_empty() {
        let dmg = (1 + ctx.abilities.modifier("str")).max(1);
        actions.push(Action {
            name: Some("Unarmed Strike".into()),
            info: Some(format!("{dmg} bludgeoning")),
            ..Default::default()
        });
    }

    let race = text(&d["race"]["fullName"])
        .or_else(|| text(&d["race"]["baseName"]))
        .map(ascii)
        .unwrap_or_default();
    let hit_die = ctx
        .primary_class()
        .and_then(|c| int(&c["definition"]["hitDice"]))
        .unwrap_or(8);
    let slots = ctx.slots();

    Ok(Character {
        key: format!("ddb{id}"),
        name: text(&d["name"])
            .map(ascii)
            .unwrap_or_else(|| "Unnamed".into()),
        race,
        class: ctx.class_label(),
        level: ctx.level,
        ac: ctx.ac(),
        hp: ctx.hp(),
        speed: ctx.speed(),
        abilities: ctx.abilities.clone(),
        saves: ctx.saves(),
        skills: ctx.skills(),
        hit_die,
        crit_range,
        // the halfling trait (reroll 1s), not the Lucky feat
        lucky: arr(&d["race"]["racialTraits"])
            .iter()
            .any(|t| t["definition"]["name"].as_str() == Some("Lucky")),
        spell_ability: if slots.is_empty()
            && !actions.iter().any(|a| a.atk.as_deref() == Some("spell"))
        {
            None
        } else {
            ctx.spell_ability().map(str::to_string)
        },
        slots,
        features,
        actions,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::modifier;

    #[test]
    fn parses_ids_and_urls() {
        assert_eq!(parse_character_id("27935516").unwrap(), 27935516);
        assert_eq!(
            parse_character_id("https://www.dndbeyond.com/characters/27935516/").unwrap(),
            27935516
        );
        assert_eq!(
            parse_character_id("https://www.dndbeyond.com/profile/x/characters/123?y=1").unwrap(),
            123
        );
        assert!(parse_character_id("hello").is_err());
    }

    #[test]
    fn helpers() {
        assert_eq!(
            ascii("Land\u{2019}s Stride \u{2014} Ren\u{e9}e"),
            "Land's Stride - Renee"
        );
        assert_eq!(camel_id("Favored Foe"), "favoredFoe");
        assert_eq!(dice_plus("1d8", -1), "1d8-1");
        assert_eq!(modifier(9), -1);
        let v = serde_json::json!({"description": "<p>Regain {{scalevalue}} hit points&nbsp;&mdash; once.</p>"});
        assert_eq!(
            rule_text(&v).as_deref(),
            Some("Regain X hit points - once.")
        );
        let v = serde_json::json!({"snippet": "a ".repeat(300)});
        assert!(rule_text(&v).unwrap().len() <= 403);
        assert_eq!(rule_text(&serde_json::json!({})), None);
    }

    fn wizard() -> Value {
        serde_json::from_str(r#"{"data": {
            "id": 1, "name": "Testy", "race": {"fullName": "High Elf", "weightSpeeds": {"normal": {"walk": 30}}},
            "stats": [{"id":1,"value":8},{"id":2,"value":14},{"id":3,"value":14},{"id":4,"value":16},{"id":5,"value":12},{"id":6,"value":10}],
            "bonusStats": [], "overrideStats": [],
            "baseHitPoints": 14, "bonusHitPoints": null, "overrideHitPoints": null,
            "modifiers": {"race": [{"type":"bonus","subType":"intelligence-score","value":1}],
                          "class": [{"type":"proficiency","subType":"intelligence-saving-throws"},{"type":"proficiency","subType":"arcana"}]},
            "classes": [{"id": 9, "level": 3, "isStartingClass": true, "definition": {"name":"Wizard","hitDice":6,"spellCastingAbilityId":4,"canCastSpells":true,
                "spellRules":{"multiClassSpellSlotDivisor":1,"levelSpellSlots":[[0,0,0,0,0,0,0,0,0],[2,0,0,0,0,0,0,0,0],[3,0,0,0,0,0,0,0,0],[4,2,0,0,0,0,0,0,0]]}},
                "classFeatures": []}],
            "inventory": [],
            "actions": {},
            "classSpells": [{"characterClassId": 9, "spells": [
                {"prepared": false, "definition": {"name":"Fire Bolt","level":0,"attackType":2,"requiresAttackRoll":true,"range":{"origin":"Ranged","rangeValue":120},
                    "modifiers":[{"type":"damage","subType":"fire","die":{"diceString":"1d10"},"atHigherLevels":{"higherLevelDefinitions":[{"level":5,"dice":{"diceString":"2d10"}}]}}]}},
                {"prepared": true, "definition": {"name":"Burning Hands","level":1,"requiresSavingThrow":true,"saveDcAbilityId":2,
                    "modifiers":[{"type":"damage","subType":"fire","die":{"diceString":"3d6"}}]}},
                {"prepared": false, "definition": {"name":"Shatter","level":2,"requiresSavingThrow":true,"saveDcAbilityId":3,
                    "modifiers":[{"type":"damage","subType":"thunder","die":{"diceString":"3d8"}}]}},
                {"prepared": true, "definition": {"name":"Magic Missile","level":1,
                    "modifiers":[{"type":"damage","subType":"force","die":{"diceString":"3d4","fixedValue":3}}]}},
                {"prepared": true, "definition": {"name":"Shield","level":1,"modifiers":[]}}
            ]}],
            "spells": {"race": [], "class": [], "item": [], "feat": []}
        }}"#).unwrap()
    }

    #[test]
    fn converts_a_wizard() {
        let c = convert(&wizard()).unwrap();
        assert_eq!(c.key, "ddb1");
        assert_eq!(c.abilities.int, 17);
        assert_eq!(c.hp, 14 + 2 * 3);
        assert_eq!(c.ac, 12);
        assert_eq!(c.slots, vec![4, 2]);
        assert_eq!(c.saves, vec!["int"]);
        assert_eq!(c.skills.get("arcana"), Some(&1));
        assert_eq!(c.spell_ability.as_deref(), Some("int"));
        let names: Vec<_> = c
            .actions
            .iter()
            .filter_map(|a| a.name.clone().or(a.section.clone()))
            .collect();
        assert_eq!(
            names,
            [
                "Cantrips",
                "Fire Bolt",
                "Spells",
                "Burning Hands",
                "Magic Missile"
            ]
        );
        let fb = &c.actions[1];
        assert_eq!(
            (fb.atk.as_deref(), fb.hit, fb.dmg.as_deref()),
            (Some("spell"), Some(5), Some("1d10"))
        );
        let bh = &c.actions[3];
        assert_eq!(
            (bh.save.as_deref(), bh.dc, bh.slot),
            (Some("dex"), Some(13), Some(1))
        );
        assert_eq!(
            (c.actions[4].auto, c.actions[4].dmg.as_deref()),
            (Some(true), Some("3d4+3"))
        );
    }
}
