use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

fn git(root: &Path, args: &[&str]) -> Option<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn main() {
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    println!("cargo:rerun-if-env-changed=NML_BUILD_COMMIT");
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=Cargo.toml");
    println!("cargo:rerun-if-changed=src");

    let checkout_commit = git(&root, &["rev-parse", "HEAD"]);
    let commit = env::var("NML_BUILD_COMMIT")
        .ok()
        .or_else(|| checkout_commit.clone())
        .unwrap_or_else(|| "unknown".into());
    assert!(
        commit == "unknown"
            || (commit.len() == 40 && commit.bytes().all(|b| b.is_ascii_hexdigit())),
        "NML_BUILD_COMMIT must be a full 40-hex commit or unknown"
    );
    let dirty = git(&root, &["status", "--porcelain"]).is_some_and(|s| !s.is_empty());

    if checkout_commit.is_some() {
        // A worktree has a .git FILE; resolve git's own paths instead of
        // assuming HEAD/refs live inside the source directory.
        for name in ["HEAD", "index", "packed-refs"] {
            if let Some(path) = git(
                &root,
                &["rev-parse", "--path-format=absolute", "--git-path", name],
            ) {
                println!("cargo:rerun-if-changed={path}");
            }
        }
        if let Some(reference) = git(&root, &["symbolic-ref", "-q", "HEAD"]) {
            if let Some(path) = git(
                &root,
                &[
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-path",
                    &reference,
                ],
            ) {
                println!("cargo:rerun-if-changed={path}");
            }
        }
        // Track source changes as well as commits/index changes, including
        // sibling core crates. Never watch ignored target/build outputs.
        if let (Some(top), Some(files)) = (
            git(&root, &["rev-parse", "--show-toplevel"]),
            git(&root, &["ls-files", "--full-name", "-z", ":/"]),
        ) {
            for file in files.split('\0').filter(|f| !f.is_empty()) {
                println!(
                    "cargo:rerun-if-changed={}",
                    Path::new(&top).join(file).display()
                );
            }
        }
    }

    let timestamp = OffsetDateTime::now_utc().format(&Rfc3339).unwrap();
    println!("cargo:rustc-env=NML_BUILD_COMMIT={commit}");
    println!("cargo:rustc-env=NML_BUILD_DIRTY={dirty}");
    println!("cargo:rustc-env=NML_BUILD_TIME_UTC={timestamp}");
}
