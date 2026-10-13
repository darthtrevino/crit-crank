//! The charsheet character format (mirrors charsheet/source/characters.lua).

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Character {
    pub key: String,
    pub name: String,
    pub race: String,
    pub class: String,
    pub level: i32,
    pub ac: i32,
    pub hp: i32,
    pub speed: i32,
    pub abilities: Abilities,
    pub saves: Vec<String>,
    /// camelCase skill key -> 1 (proficient) or 2 (expertise)
    pub skills: BTreeMap<String, u8>,
    pub hit_die: i32,
    pub crit_range: i32,
    pub lucky: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub spell_ability: Option<String>,
    pub slots: Vec<i32>,
    pub features: Vec<Feature>,
    pub actions: Vec<Action>,
    /// TRAITS page; omitted when empty so older readers see the same file.
    #[serde(default, skip_serializing_if = "Traits::is_empty")]
    pub traits: Traits,
}

/// Speeds other than walking, senses, languages, defenses and proficiencies.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase", default)]
pub struct Traits {
    /// fly, swim, climb, burrow -> feet
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub speeds: BTreeMap<String, i32>,
    /// darkvision, blindsight, tremorsense, truesight -> feet
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub senses: BTreeMap<String, i32>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub languages: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub resistances: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub immunities: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub vulnerabilities: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub condition_immunities: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub armor: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub weapons: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tools: Vec<String>,
}

impl Traits {
    pub fn is_empty(&self) -> bool {
        *self == Traits::default()
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Abilities {
    pub str: i32,
    pub dex: i32,
    pub con: i32,
    pub int: i32,
    pub wis: i32,
    pub cha: i32,
}

impl Abilities {
    pub fn get(&self, ab: &str) -> i32 {
        match ab {
            "str" => self.str,
            "dex" => self.dex,
            "con" => self.con,
            "int" => self.int,
            "wis" => self.wis,
            _ => self.cha,
        }
    }

    pub fn set(&mut self, ab: &str, v: i32) {
        match ab {
            "str" => self.str = v,
            "dex" => self.dex = v,
            "con" => self.con = v,
            "int" => self.int = v,
            "wis" => self.wis = v,
            _ => self.cha = v,
        }
    }

    pub fn modifier(&self, ab: &str) -> i32 {
        modifier(self.get(ab))
    }
}

pub fn modifier(score: i32) -> i32 {
    (score - 10).div_euclid(2)
}

pub fn proficiency(level: i32) -> i32 {
    2 + (level.max(1) - 1) / 4
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Feature {
    pub id: String,
    pub name: String,
    pub max: i32,
    /// "short" or "long"
    pub reset: String,
    /// Rule text shown on the pause screen.
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub rule: Option<String>,
}

/// One row (or row group) on the ACTIONS page. Exactly one of
/// section / info / heal / atk / save / auto / plain dmg applies.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Action {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub section: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub atk: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hit: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub save: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dc: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub auto: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dmg: Option<String>,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub heal: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub self_heal: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub info: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub slot: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uses: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub critable: Option<bool>,
    /// Rule text shown on the pause screen.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rule: Option<String>,
}

impl Action {
    pub fn section(title: &str) -> Self {
        Action {
            section: Some(title.to_string()),
            ..Default::default()
        }
    }
}
