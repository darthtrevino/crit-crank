mod ddb;
mod model;
mod transport;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use std::path::PathBuf;
use transport::Device;

/// Sync D&D Beyond characters to charsheet on a Playdate.
#[derive(Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
    /// Serial port of the Playdate (auto-detected by default)
    #[arg(long, global = true)]
    port: Option<String>,
    /// Log serial traffic
    #[arg(short, long, global = true)]
    verbose: bool,
}

#[derive(Subcommand)]
enum Cmd {
    /// Import a public D&D Beyond character (id or URL)
    Import {
        /// Character id or https://www.dndbeyond.com/characters/<id> URL
        character: Option<String>,
        /// Read D&D Beyond JSON from a file instead of downloading
        #[arg(long, value_name = "FILE")]
        file: Option<PathBuf>,
        /// Install into the Playdate Simulator's data folder
        #[arg(long, conflicts_with_all = ["disk", "out"])]
        simulator: bool,
        /// Copy via USB disk mode instead of live serial transfer
        #[arg(long, conflicts_with = "out")]
        disk: bool,
        /// Disk mount point to use with --disk (auto-detected by default)
        #[arg(long, requires = "disk")]
        mount: Option<PathBuf>,
        /// Just write the converted character JSON ("-" for stdout)
        #[arg(long, value_name = "FILE")]
        out: Option<PathBuf>,
        /// Don't launch charsheet if it isn't running
        #[arg(long)]
        no_launch: bool,
    },
    /// Remove an imported character by key (e.g. ddb27935516)
    Remove {
        key: String,
        #[arg(long)]
        simulator: bool,
    },
    /// Check that charsheet is running and reachable over USB
    Ping,
    /// List serial ports
    Ports,
}

fn main() {
    if let Err(e) = run(Cli::parse()) {
        eprintln!("error: {e:#}");
        std::process::exit(1);
    }
}

fn open_device(cli_port: &Option<String>, verbose: bool) -> Result<(String, Device)> {
    let port = match cli_port {
        Some(p) => p.clone(),
        None => transport::find_playdate()?,
    };
    let mut dev = Device::open(&port)?;
    dev.verbose = verbose;
    Ok((port, dev))
}

fn run(cli: Cli) -> Result<()> {
    match cli.cmd {
        Cmd::Ports => {
            for (name, pd) in transport::list_ports()? {
                println!("{name}{}", if pd { "  (Playdate)" } else { "" });
            }
        }
        Cmd::Ping => {
            let (port, mut dev) = open_device(&cli.port, cli.verbose)?;
            if dev.ping()? {
                println!("charsheet is running on {port}");
            } else {
                bail!("found a Playdate on {port}, but charsheet isn't responding. Is it open?");
            }
        }
        Cmd::Remove { key, simulator } => {
            if simulator {
                let dir = transport::data_dir(&transport::simulator_disk()?);
                if !transport::remove_import(&dir, &key)? {
                    bail!("{key} isn't imported in the Simulator");
                }
            } else {
                let (_, mut dev) = open_device(&cli.port, cli.verbose)?;
                dev.ensure_running(false)?;
                dev.remove(&key)?;
            }
            println!("Removed {key}");
        }
        Cmd::Import { character, file, simulator, disk, mount, out, no_launch } => {
            let raw = match (&file, &character) {
                (Some(f), _) => {
                    let s = std::fs::read_to_string(f).with_context(|| format!("reading {}", f.display()))?;
                    serde_json::from_str(&s).context("file isn't valid JSON")?
                }
                (None, Some(c)) => {
                    let id = ddb::parse_character_id(c)?;
                    eprintln!("Fetching character {id} from D&D Beyond...");
                    ddb::fetch(id)?
                }
                (None, None) => bail!("give a character id/URL or --file"),
            };
            let c = ddb::convert(&raw)?;
            let json = serde_json::to_string(&c)?;
            let label = format!("{} (Lv{} {} {}, key {})", c.name, c.level, c.race, c.class, c.key);

            if let Some(out) = out {
                let pretty = serde_json::to_string_pretty(&c)?;
                if out.as_os_str() == "-" {
                    println!("{pretty}");
                } else {
                    std::fs::write(&out, pretty)?;
                    eprintln!("Wrote {label} to {}", out.display());
                }
            } else if simulator {
                let path = transport::write_import(&transport::data_dir(&transport::simulator_disk()?), &c)?;
                println!("Installed {label} in the Simulator ({}). Relaunch charsheet to see it.", path.display());
            } else if disk {
                let root = match mount.or_else(transport::find_mount) {
                    Some(m) => m,
                    None => {
                        let port = match &cli.port {
                            Some(p) => p.clone(),
                            None => transport::find_playdate()?,
                        };
                        transport::enter_disk_mode(&port)?
                    }
                };
                transport::write_import(&transport::data_dir(&root), &c)?;
                transport::eject(&root)?;
                if transport::relaunch(cli.port.as_deref()) {
                    println!("Copied {label} to the Playdate and relaunched charsheet.");
                } else {
                    println!("Copied {label} to the Playdate. Open charsheet to see it.");
                }
            } else {
                let (_, mut dev) = open_device(&cli.port, cli.verbose)?;
                dev.ensure_running(!no_launch)?;
                eprintln!("Sending {} bytes...", json.len());
                dev.push(&json)?;
                println!("Imported {label}. It's now selected in charsheet.");
            }
        }
    }
    Ok(())
}
