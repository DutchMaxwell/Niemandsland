//! Loopback HTTP transport only: no environment reads or search wiring.
use serde_json::Value;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream};
use std::time::{Duration, Instant};

#[derive(Debug, PartialEq)]
pub enum Error {
    Declined(&'static str),
    Length(usize, usize),
}

const MAX_BODY: usize = 65536;
fn decline(reason: &'static str) -> Error { Error::Declined(reason) }

fn address(url: &str) -> Result<SocketAddr, Error> {
    let authority = url.strip_prefix("http://").ok_or_else(|| decline("URL"))?;
    let addr: SocketAddr = authority.trim_end_matches('/').parse().map_err(|_| decline("URL"))?;
    if !addr.ip().is_loopback() || addr.port() == 0 { return Err(decline("LoopbackOnly")); }
    Ok(addr)
}

fn remaining(deadline: Instant) -> Result<Duration, Error> {
    deadline.checked_duration_since(Instant::now()).filter(|d| !d.is_zero())
        .ok_or_else(|| decline("Timeout"))
}

fn io_error(e: std::io::Error) -> Error {
    match e.kind() {
        std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock => decline("Timeout"),
        _ => decline("Transport"),
    }
}

pub fn exchange(url: &str, timeout_ms: u64, request: &Value) -> Result<Value, Error> {
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let addr = address(url)?;
    let body = serde_json::to_vec(request).map_err(|_| decline("Request"))?;
    if body.len() > 16 * 1024 * 1024 { return Err(decline("RequestTooLarge")); }
    let mut stream = TcpStream::connect_timeout(&addr, remaining(deadline)?).map_err(io_error)?;
    let header = format!("POST / HTTP/1.1\r\nHost: {addr}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", body.len());
    for bytes in [header.as_bytes(), body.as_slice()] {
        let mut rest = bytes;
        while !rest.is_empty() {
            stream.set_write_timeout(Some(remaining(deadline)?)).map_err(io_error)?;
            let n = stream.write(rest).map_err(io_error)?;
            if n == 0 { return Err(decline("Transport")); }
            rest = &rest[n..];
        }
    }
    let mut bytes = Vec::new();
    let mut end = None;
    let mut total = None;
    loop {
        stream.set_read_timeout(Some(remaining(deadline)?)).map_err(io_error)?;
        let mut block = [0; 4096];
        let n = stream.read(&mut block).map_err(io_error)?;
        if n == 0 { return Err(decline("TruncatedResponse")); }
        bytes.extend_from_slice(&block[..n]);
        if end.is_none() {
            if let Some(i) = bytes.windows(4).position(|w| w == b"\r\n\r\n") {
                if i > 8192 { return Err(decline("ResponseTooLarge")); }
                let text = std::str::from_utf8(&bytes[..i]).map_err(|_| decline("HTTP"))?;
                let mut lines = text.split("\r\n");
                let status = lines.next().unwrap_or("").split_whitespace().collect::<Vec<_>>();
                if status.len() < 2 || status[1] != "200" { return Err(decline("HTTPStatus")); }
                let mut length = None;
                for line in lines {
                    let (key, value) = line.split_once(':').ok_or_else(|| decline("HTTP"))?;
                    if key.eq_ignore_ascii_case("transfer-encoding") { return Err(decline("HTTP")); }
                    if key.eq_ignore_ascii_case("content-length") {
                        if length.is_some() { return Err(decline("HTTP")); }
                        length = Some(value.trim().parse::<usize>().map_err(|_| decline("HTTP"))?);
                    }
                }
                let length = length.filter(|n| *n <= MAX_BODY).ok_or_else(|| decline("ResponseTooLarge"))?;
                end = Some(i + 4);
                total = Some(i + 4 + length);
            } else if bytes.len() > 8192 { return Err(decline("ResponseTooLarge")); }
        }
        if let Some(total) = total {
            if bytes.len() >= total {
                let response: Value = serde_json::from_slice(&bytes[end.unwrap()..total]).map_err(|_| decline("JSON"))?;
                if response.get("schema").and_then(Value::as_u64) != Some(1) { return Err(decline("Schema")); }
                let values = response["values"].as_array().ok_or_else(|| decline("Values"))?;
                let n = request["leaves"].as_array().ok_or_else(|| decline("Request"))?.len();
                if values.len() != n { return Err(Error::Length(values.len(), n)); }
                if values.iter().any(|v| !v.as_f64().is_some_and(f64::is_finite)) { return Err(decline("Values")); }
                for key in ["name", "hash"] {
                    if !response["brain"][key].as_str().is_some_and(|s| !s.is_empty() && s.len() <= 128 && !s.chars().any(char::is_control)) {
                        return Err(decline("BrainIdentity"));
                    }
                }
                return Ok(response);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::thread;
    use std::time::{Duration, Instant};
    use serde_json::json;

    fn fake(body: Value, delay: u64) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        listener.set_nonblocking(true).unwrap();
        thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(2);
            while Instant::now() < deadline {
                if let Ok((mut stream, _)) = listener.accept() {
                    stream.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
                    let mut buf = [0; 65536];
                    let _ = stream.read(&mut buf);
                    thread::sleep(Duration::from_millis(delay));
                    let body = body.to_string();
                    let _ = write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body);
                    return;
                }
                thread::sleep(Duration::from_millis(2));
            }
        });
        url
    }

    fn request() -> Value {
        json!({"schema":1,"core_commit":"unknown","rules_epoch":6,"side":1,"leaves":[{}]})
    }

    #[test]
    fn brain_constant_batch_is_consumed() {
        let body = json!({"schema":1,"values":[0.25],"brain":{"name":"dummy","hash":"test"}});
        let answer = exchange(&fake(body.clone(), 0), 200, &request());
        assert!(answer.is_ok(), "expected the leaf client, got {answer:?}");
        assert_eq!(answer.unwrap(), body);
    }

    #[test]
    fn brain_schema_length_and_metadata_fail_closed() {
        for body in [json!({"schema":2,"values":[0.0],"brain":{"name":"dummy","hash":"test"}}),
                     json!({"schema":1,"values":[],"brain":{"name":"dummy","hash":"test"}}),
                     json!({"schema":1,"values":[null],"brain":{"name":"dummy","hash":"test"}}),
                     json!({"schema":1,"values":[0.0]})] {
            assert!(exchange(&fake(body, 0), 200, &request()).is_err());
        }
    }

    #[test]
    fn brain_timeout_and_non_loopback_decline() {
        let start = Instant::now();
        assert!(exchange(&fake(json!({}), 300), 30, &request()).is_err());
        assert!(start.elapsed() < Duration::from_millis(250));
        for url in ["http://example.com:80", "http://192.168.1.1:80", "https://127.0.0.1:80", "http://user@127.0.0.1:80"] {
            assert!(exchange(url, 200, &request()).is_err());
        }
    }

    #[test]
    fn a_closed_server_returns_no_value() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        drop(listener);
        assert_eq!(exchange(&url, 100, &request()), Err(Error::Declined("Transport")));
    }

    #[test]
    fn sends_one_complete_length_delimited_batch() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let sent = request();
        let expected = sent.clone();
        let server = thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
            let mut header = Vec::new();
            while !header.ends_with(b"\r\n\r\n") {
                let mut byte = [0];
                stream.read_exact(&mut byte).unwrap();
                header.push(byte[0]);
            }
            let header = String::from_utf8(header).unwrap();
            assert!(header.starts_with("POST / HTTP/1.1\r\n"));
            assert!(header.contains("Content-Type: application/json\r\n"));
            let length = header.lines().find_map(|line| line.strip_prefix("Content-Length: ")).unwrap().parse().unwrap();
            let mut body = vec![0; length];
            stream.read_exact(&mut body).unwrap();
            assert_eq!(serde_json::from_slice::<Value>(&body).unwrap(), expected);
            let reply = json!({"schema":1,"values":[0.5],"brain":{"name":"stub","hash":"fixed"}}).to_string();
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}", reply.len(), reply).unwrap();
        });
        assert_eq!(exchange(&url, 1000, &sent).unwrap()["values"], json!([0.5]));
        server.join().unwrap();
    }

    fn raw_reply(reply: &'static [u8], drip: bool) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream.set_read_timeout(Some(Duration::from_secs(2))).unwrap();
            let _ = stream.read(&mut [0; 4096]);
            if drip {
                for byte in reply {
                    if stream.write_all(&[*byte]).is_err() { break; }
                    thread::sleep(Duration::from_millis(5));
                }
            } else {
                let _ = stream.write_all(reply);
            }
        });
        url
    }

    #[test]
    fn malformed_framing_never_produces_values() {
        for reply in [
            b"HTTP/1.1 302 Found\r\nContent-Length: 0\r\n\r\n".as_slice(),
            b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 2\r\n\r\n{}",
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            b"HTTP/1.1 200 OK\r\nContent-Length: 999999999\r\n\r\n",
            b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n{}",
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n!",
        ] {
            assert!(exchange(&raw_reply(reply, false), 200, &request()).is_err());
        }
    }

    #[test]
    fn deadline_is_total_not_restarted_by_partial_reads() {
        let url = raw_reply(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n{}", true);
        let start = Instant::now();
        assert_eq!(exchange(&url, 40, &request()), Err(Error::Declined("Timeout")));
        assert!(start.elapsed() < Duration::from_millis(200));
    }
}
