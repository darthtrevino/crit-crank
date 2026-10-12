//! Getting characters onto the Playdate: USB serial, data-disk mode, or the Simulator.

use crate::model::Character;
use anyhow::{Context, Result, bail};
use serde_json::{Value, json};
use std::io::{ErrorKind, Read, Write};
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::{Duration, Instant};

pub const BUNDLE_ID: &str = "com.christrevino.charsheet";
pub const GAME_PATH: &str = "/Games/charsheet.pdx";
const PLAYDATE_VID: u16 = 0x1331;
const CHUNK: usize = 180;

// ---------------------------------------------------------------- serial

pub fn list_ports() -> Result<Vec<(String, bool)>> {
    let ports = serialport::available_ports().context("listing serial ports")?;
    Ok(ports
        .into_iter()
        .map(|p| {
            let is_pd = matches!(&p.port_type, serialport::SerialPortType::UsbPort(u) if u.vid == PLAYDATE_VID)
                || p.port_name.contains("PDU1");
            (p.port_name, is_pd)
        })
        .collect())
}

pub fn find_playdate() -> Result<String> {
    let mut found: Vec<String> = list_ports()?.into_iter().filter(|(_, pd)| *pd).map(|(n, _)| n).collect();
    // macOS lists both /dev/tty.* and /dev/cu.*; cu doesn't wait for carrier
    found.sort_by_key(|n| !n.contains("/cu."));
    found.into_iter().next().context(
        "no Playdate found over USB. Plug it in, unlock it, and make sure it isn't in disk mode (or pass --port)",
    )
}

pub struct Device {
    port: Box<dyn serialport::SerialPort>,
    pending: String,
    pub verbose: bool,
}

impl Device {
    pub fn open(name: &str) -> Result<Self> {
        let port = serialport::new(name, 115_200)
            .timeout(Duration::from_millis(50))
            .open()
            .with_context(|| format!("opening {name} (is pdutil or the Simulator using it?)"))?;
        Ok(Device { port, pending: String::new(), verbose: false })
    }

    fn send(&mut self, line: &str) -> Result<()> {
        if self.verbose {
            eprintln!("> {line}");
        }
        self.port.write_all(format!("{line}\n").as_bytes())?;
        self.port.flush()?;
        Ok(())
    }

    fn drain(&mut self) {
        let mut buf = [0u8; 1024];
        let until = Instant::now() + Duration::from_millis(100);
        while Instant::now() < until {
            if !matches!(self.port.read(&mut buf), Ok(n) if n > 0) {
                break;
            }
        }
        self.pending.clear();
    }

    /// Waits for a line starting with "cs " from the game.
    fn reply(&mut self, timeout: Duration) -> Result<Option<String>> {
        let deadline = Instant::now() + timeout;
        let mut buf = [0u8; 1024];
        loop {
            while let Some(nl) = self.pending.find('\n') {
                let line: String = self.pending.drain(..=nl).collect();
                let line = line.trim();
                if self.verbose && !line.is_empty() {
                    eprintln!("< {line}");
                }
                // the console echoes our "msg cs ..." commands; only game replies start with "cs "
                if line.starts_with("cs ") {
                    return Ok(Some(line.to_string()));
                }
            }
            if Instant::now() >= deadline {
                return Ok(None);
            }
            match self.port.read(&mut buf) {
                Ok(n) => self.pending.push_str(&String::from_utf8_lossy(&buf[..n])),
                Err(e) if e.kind() == ErrorKind::TimedOut || e.kind() == ErrorKind::WouldBlock => {}
                Err(e) => return Err(e).context("reading from Playdate"),
            }
        }
    }

    fn request(&mut self, msg: &str, timeout: Duration) -> Result<Option<String>> {
        self.send(&format!("msg cs {msg}"))?;
        self.reply(timeout)
    }

    pub fn ping(&mut self) -> Result<bool> {
        self.drain();
        Ok(matches!(self.request("ping", Duration::from_millis(1500))?, Some(r) if r.starts_with("cs pong")))
    }

    /// Pings the game, launching it first if it isn't running.
    pub fn ensure_running(&mut self, launch: bool) -> Result<()> {
        if self.ping()? {
            return Ok(());
        }
        if !launch {
            bail!("charsheet isn't responding. Open it on the Playdate and try again");
        }
        eprintln!("Launching charsheet on the Playdate...");
        self.send(&format!("run {GAME_PATH}"))?;
        let deadline = Instant::now() + Duration::from_secs(15);
        while Instant::now() < deadline {
            sleep(Duration::from_millis(1000));
            if self.ping()? {
                return Ok(());
            }
        }
        bail!("charsheet didn't answer. Open it on the Playdate (it must be installed at {GAME_PATH}) and try again")
    }

    pub fn push(&mut self, json: &str) -> Result<String> {
        if !json.is_ascii() || json.contains('\n') {
            bail!("internal error: payload must be single-line ASCII");
        }
        let chunks = chunk(json);
        self.expect(&format!("begin {}", json.len()), "cs ready")?;
        for (i, c) in chunks.iter().enumerate() {
            let seq = i + 1;
            self.expect(&format!("data {seq} {c}"), &format!("cs ack {seq}"))
                .with_context(|| format!("sending chunk {seq}/{}", chunks.len()))?;
        }
        let done = self.expect("end", "cs done ")?;
        Ok(done.trim_start_matches("cs done ").to_string())
    }

    pub fn remove(&mut self, key: &str) -> Result<()> {
        self.expect(&format!("remove {key}"), "cs removed ").map(|_| ())
    }

    fn expect(&mut self, msg: &str, want: &str) -> Result<String> {
        for _ in 0..3 {
            match self.request(msg, Duration::from_secs(2))? {
                Some(r) if r.starts_with(want) => return Ok(r),
                Some(r) if r.starts_with("cs err") => bail!("Playdate: {}", r.trim_start_matches("cs err ")),
                _ => continue, // lost or stale reply: resend (the game re-acks duplicates)
            }
        }
        bail!("no reply from charsheet (expected {want:?})")
    }
}

/// Splits into chunks of at most CHUNK bytes, never starting or ending on
/// whitespace (the serial console may trim it).
fn chunk(s: &str) -> Vec<&str> {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut start = 0;
    while start < b.len() {
        let mut end = (start + CHUNK).min(b.len());
        while end < b.len() && end > start + 1 && (b[end - 1] == b' ' || b[end] == b' ') {
            end -= 1;
        }
        out.push(&s[start..end]);
        start = end;
    }
    out
}

// ---------------------------------------------------------------- disk mode

/// Puts the device into data-disk mode and waits for the volume to mount.
pub fn enter_disk_mode(port: &str) -> Result<PathBuf> {
    if let Some(m) = find_mount() {
        return Ok(m);
    }
    let mut dev = Device::open(port)?;
    dev.send("datadisk")?;
    drop(dev);
    eprintln!("Waiting for the Playdate disk to mount...");
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        sleep(Duration::from_millis(500));
        if let Some(m) = find_mount() {
            sleep(Duration::from_millis(500));
            return Ok(m);
        }
    }
    bail!("the PLAYDATE disk didn't appear. If it's mounted somewhere unusual, pass --mount <path>")
}

pub fn find_mount() -> Option<PathBuf> {
    let looks_right = |p: &Path| p.join("Games").is_dir() && p.join("Data").is_dir();
    let mut candidates = vec![PathBuf::from("/Volumes/PLAYDATE")];
    if let Ok(user) = std::env::var("USER") {
        candidates.push(PathBuf::from(format!("/media/{user}/PLAYDATE")));
        candidates.push(PathBuf::from(format!("/run/media/{user}/PLAYDATE")));
    }
    candidates.push(PathBuf::from("/media/PLAYDATE"));
    if cfg!(windows) {
        candidates.extend((b'D'..=b'Z').map(|l| PathBuf::from(format!("{}:\\", l as char))));
        // only accept a drive letter that has the Playdate's System folder too
        return candidates.into_iter().find(|p| looks_right(p) && p.join("System").is_dir());
    }
    candidates.into_iter().find(|p| looks_right(p))
}

/// Best effort: waits for the device to leave disk mode, then launches charsheet.
pub fn relaunch(port: Option<&str>) -> bool {
    let deadline = Instant::now() + Duration::from_secs(30);
    sleep(Duration::from_secs(2));
    while Instant::now() < deadline {
        let name = match port {
            Some(p) => Some(p.to_string()),
            None => find_playdate().ok(),
        };
        if let Some(mut dev) = name.and_then(|n| Device::open(&n).ok()) {
            sleep(Duration::from_secs(1));
            return dev.ensure_running(true).is_ok();
        }
        sleep(Duration::from_millis(500));
    }
    false
}

pub fn eject(mount: &Path) -> Result<()> {
    if !(cfg!(target_os = "macos") || cfg!(target_os = "linux")) {
        eprintln!("Eject the PLAYDATE drive from the system tray, then press A on the Playdate.");
        return Ok(());
    }
    // antivirus scanners often hold freshly written files for a moment
    for attempt in 0..6 {
        if attempt > 0 {
            sleep(Duration::from_secs(2));
        }
        let status = if cfg!(target_os = "macos") {
            std::process::Command::new("diskutil").arg("eject").arg(mount).stderr(std::process::Stdio::null()).status()
        } else {
            std::process::Command::new("umount").arg(mount).stderr(std::process::Stdio::null()).status()
        };
        if matches!(status, Ok(s) if s.success()) {
            return Ok(());
        }
    }
    bail!("couldn't eject {}; eject it manually and press A on the Playdate", mount.display())
}

// ---------------------------------------------------------------- data folder

/// The game's datastore folder under a Playdate disk (device mount or Simulator Disk/).
pub fn data_dir(disk_root: &Path) -> PathBuf {
    disk_root.join("Data").join(BUNDLE_ID)
}

pub fn simulator_disk() -> Result<PathBuf> {
    let mut roots = Vec::new();
    if let Ok(p) = std::env::var("PLAYDATE_SDK_PATH") {
        roots.push(PathBuf::from(p));
    }
    let home = std::env::var("HOME").or_else(|_| std::env::var("USERPROFILE")).map(PathBuf::from).ok();
    if let Some(home) = &home {
        // ~/.Playdate/config holds "SDKRoot <path>" on Linux/Windows installs
        if let Ok(cfg) = std::fs::read_to_string(home.join(".Playdate").join("config")) {
            for line in cfg.lines() {
                if let Some(p) = line.strip_prefix("SDKRoot") {
                    roots.push(PathBuf::from(p.trim()));
                }
            }
        }
        roots.push(home.join("Developer").join("PlaydateSDK"));
        roots.push(home.join("Documents").join("PlaydateSDK"));
    }
    roots
        .into_iter()
        .map(|r| r.join("Disk"))
        .find(|d| d.is_dir())
        .context("couldn't find the Playdate SDK. Set PLAYDATE_SDK_PATH")
}

/// Inserts or replaces a character in <dir>/imports.json, keeping the others.
pub fn write_import(dir: &Path, c: &Character) -> Result<PathBuf> {
    std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    let path = dir.join("imports.json");
    let mut list = read_imports(&path)?;
    let value = serde_json::to_value(c)?;
    match list.iter_mut().find(|v| v["key"] == value["key"]) {
        Some(slot) => *slot = value,
        None => list.push(value),
    }
    write_list(&path, list)?;
    Ok(path)
}

pub fn remove_import(dir: &Path, key: &str) -> Result<bool> {
    let path = dir.join("imports.json");
    let mut list = read_imports(&path)?;
    let before = list.len();
    list.retain(|v| v["key"].as_str() != Some(key));
    let removed = list.len() != before;
    if removed {
        write_list(&path, list)?;
    }
    Ok(removed)
}

fn read_imports(path: &Path) -> Result<Vec<Value>> {
    match std::fs::read_to_string(path) {
        Ok(s) => {
            let v: Value = serde_json::from_str(&s).with_context(|| format!("{} is corrupt", path.display()))?;
            Ok(v["characters"].as_array().cloned().unwrap_or_default())
        }
        Err(e) if e.kind() == ErrorKind::NotFound => Ok(Vec::new()),
        Err(e) => Err(e).with_context(|| format!("reading {}", path.display())),
    }
}

fn write_list(path: &Path, list: Vec<Value>) -> Result<()> {
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, serde_json::to_string(&json!({ "characters": list }))?)?;
    std::fs::rename(&tmp, path).with_context(|| format!("writing {}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_cover_input_and_avoid_edge_spaces() {
        let s = format!("{}{}", "a".repeat(179), "\"Two words\",".repeat(80));
        let parts = chunk(&s);
        assert_eq!(parts.concat(), s);
        for p in &parts[..parts.len() - 1] {
            assert!(p.len() <= CHUNK && !p.ends_with(' ') && !p.starts_with(' '), "{p:?}");
        }
    }
}
