//! Developer leaf hook; HTTP framing lives in the separately tested transport.
use nml_core::sim::Unsupported;
use serde_json::{Value, json};
use std::cell::{Cell, RefCell};
use std::time::Instant;
use nml_core::{plan::LeafValue, rows::RowEncoder, state::State, terrain::Terrain, unit::UnitStatic};
use super::brain_transport::{self, Error};

fn decline(reason: &'static str) -> Unsupported { Unsupported::LeafValueBridge(reason) }
fn exchange(url: &str, timeout: u64, request: &Value) -> Result<Value, Unsupported> {
    brain_transport::exchange(url, timeout, request).map_err(|e| match e {
        Error::Declined(reason) => decline(reason),
        Error::Length(given, expected) => Unsupported::LeafValue(given, expected),
    })
}

pub struct Client {
    pub url: String,
    pub weight: f64,
    timeout_ms: u64,
    pub identity: Value,
    pub batches: Cell<u64>,
    pub micros: Cell<u64>,
}

impl Client {
    pub fn from_env(developer: bool) -> Option<Result<Self, String>> {
        let url = std::env::var("NML_BRAIN_URL").unwrap_or_default();
        if url.is_empty() { return None; }
        Some((|| {
            if !developer { return Err(decline("DeveloperOnly")); }
            let weight: f64 = std::env::var("NML_BRAIN_W").unwrap_or_else(|_| "1".into()).parse().map_err(|_| decline("Weight"))?;
            if !weight.is_finite() || weight <= 0.0 { return Err(decline("Weight")); }
            let timeout_ms: u64 = std::env::var("NML_BRAIN_TIMEOUT_MS").unwrap_or_else(|_| "200".into()).parse().map_err(|_| decline("TimeoutConfig"))?;
            if !(1..=10000).contains(&timeout_ms) { return Err(decline("TimeoutConfig")); }
            let response = exchange(&url, timeout_ms, &request(1, vec![]))?;
            Ok(Self { url, weight, timeout_ms, identity: response["brain"].clone(), batches: Cell::new(0), micros: Cell::new(0) })
        })().map_err(|e: Unsupported| format!("{e:?}")))
    }
}

fn request(side: i64, leaves: Vec<Value>) -> Value {
    json!({"schema":1,"core_commit":env!("NML_BUILD_COMMIT"),
           "rules_epoch":nml_core::acts::CURRENT_RULES_EPOCH,"side":side,"leaves":leaves})
}

pub struct Hook<'a> {
    pub client: &'a Client,
    pub statics: &'a [UnitStatic],
    pub terrain: &'a Terrain,
    pub rows: RefCell<RowEncoder>,
    pub hero_attach: bool,
    pub opener_seat: bool,
}

impl LeafValue for Hook<'_> {
    fn value(&self, leaves: &[&State], side: i64) -> Result<Vec<f64>, Unsupported> {
        let started = Instant::now();
        let mut rows = self.rows.borrow_mut();
        let batch = leaves.iter().map(|state| {
            nml_core::tokens::build(state, side, self.statics, self.terrain, &mut rows,
                &[], -1, self.hero_attach, self.opener_seat).map(|t| t.to_json())
        }).collect::<Result<Vec<_>, _>>()?;
        let response = exchange(&self.client.url, self.client.timeout_ms, &request(side, batch))?;
        if response["brain"] != self.client.identity { return Err(decline("BrainChanged")); }
        self.client.batches.set(self.client.batches.get() + 1);
        self.client.micros.set(self.client.micros.get() + started.elapsed().as_micros() as u64);
        Ok(response["values"].as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;
    use std::time::Duration;

    #[test]
    fn live_search_consumes_one_http_leaf_batch() {
        let root = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
        let fixture = format!("{root}/core/nml-core/tests/fixtures/acts_25.jsonl");
        let corpus = nml_core::load_acts(&fixture).unwrap();
        let statics = nml_core::build_act_statics(&corpus, root);
        let act = &corpus.acts[0];
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        listener.set_nonblocking(true).unwrap();
        let server = thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(3);
            while Instant::now() < deadline {
                let Ok((mut stream, _)) = listener.accept() else {
                    thread::sleep(Duration::from_millis(2));
                    continue;
                };
                stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
                let mut header = Vec::new();
                while !header.ends_with(b"\r\n\r\n") {
                    let mut byte = [0];
                    stream.read_exact(&mut byte).unwrap();
                    header.push(byte[0]);
                }
                let text = String::from_utf8(header).unwrap();
                let size = text.lines().find_map(|s| s.strip_prefix("Content-Length: ")).unwrap().parse().unwrap();
                let mut body = vec![0; size];
                stream.read_exact(&mut body).unwrap();
                let request: Value = serde_json::from_slice(&body).unwrap();
                assert_eq!(request["core_commit"], env!("NML_BUILD_COMMIT"));
                assert_eq!(request["rules_epoch"], nml_core::acts::CURRENT_RULES_EPOCH);
                let leaves = request["leaves"].as_array().unwrap();
                assert!(!leaves.is_empty());
                for leaf in leaves {
                    assert_eq!(leaf.as_object().unwrap().len(), 12);
                    assert_eq!(leaf["units"].as_array().unwrap().len(), nml_core::tokens::N_UNITS);
                    assert_eq!(leaf["label"], -1);
                    assert!(leaf["cands_mask"].as_array().unwrap().iter().all(|v| v == 0));
                }
                let body = json!({"schema":1,"values":vec![0.25; leaves.len()],
                    "brain":{"name":"search-stub","hash":"fixed"}}).to_string();
                write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}", body.len(), body).unwrap();
                return;
            }
            panic!("search never called the brain server");
        });
        let client = Client { url, weight:1.0, timeout_ms:2000,
            identity:json!({"name":"search-stub","hash":"fixed"}), batches:Cell::new(0), micros:Cell::new(0) };
        let hook = Hook { client:&client, statics:&statics, terrain:&corpus.terrain,
            rows:RefCell::new(RowEncoder::new(root)), hero_attach:corpus.knobs.hero_attach,
            opener_seat:act.statics.opener_seat };
        let result = nml_core::plan::plan_with_leaf_value(&act.state, &corpus.terrain, &statics,
            &corpus.knobs, &act.statics, act.player, None, Some(&hook), 1.0);
        assert!(result.is_ok(), "HTTP leaf hook did not reach the search: {result:?}");
        assert_eq!(client.batches.get(), 1);
        eprintln!("BRAIN_LATENCY batches_per_activation={} batch_ms={:.3}",
            client.batches.get(), client.micros.get() as f64 / 1000.0);
        server.join().unwrap();
    }
}
