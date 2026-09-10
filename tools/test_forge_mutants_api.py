import contextlib
import json
import sys
import urllib.error
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import forge_mutants as fm

class Resp:
    def __init__(self, body, status=200):
        self.body, self.status = body, status
    def read(self):
        return self.body

def fake(monkeypatch, handler):
    seen = {}
    def open_(req, timeout=None):
        seen['url'] = req.full_url
        seen['body'] = json.loads(req.data)
        return contextlib.nullcontext(handler(seen['url']))
    monkeypatch.setattr(fm.urllib.request, 'urlopen', open_)
    return seen

def reply(obj):
    return lambda url: Resp(json.dumps(obj).encode())

def test_openai_transport(monkeypatch):
    seen = fake(monkeypatch, reply({'choices': [{'message': {'content': 'X'}}]}))
    data = fm.call_openai('http://h:8080', 'm', 'P')
    assert seen['url'] == 'http://h:8080/v1/chat/completions'
    assert seen['body'] == {'model': 'm', 'messages': [{'role': 'user', 'content': 'P'}], 'stream': False, 'temperature': 0}
    assert fm.extract_reply(data, 'openai', seen['url']) == 'X'

def test_ollama_transport(monkeypatch):
    seen = fake(monkeypatch, reply({'response': 'Y'}))
    data = fm.call_ollama('http://h:11434/api/generate', 'm', 'P')
    assert seen['url'] == 'http://h:11434/api/generate'
    assert seen['body'] == {'model': 'm', 'prompt': 'P', 'stream': False, 'options': {'num_ctx': 8192, 'temperature': 0.2}}
    assert fm.extract_reply(data, 'ollama', seen['url']) == 'Y'

def test_loud_failures(monkeypatch):
    def boom(url):
        raise urllib.error.HTTPError(url, 500, 'err', {}, None)
    fake(monkeypatch, boom)
    with pytest.raises(Exception) as e:
        fm.call_openai('http://h:8080', 'm', 'P')
    assert '500' in str(e.value) and 'http://h:8080/v1/chat/completions' in str(e.value)
    fake(monkeypatch, lambda url: Resp(b'not json'))
    with pytest.raises(Exception) as e:
        fm.call_ollama('http://h:11434/api/generate', 'm', 'P')
    assert 'http://h:11434/api/generate' in str(e.value)
    seen = fake(monkeypatch, reply({'nope': 1}))
    data = fm.call_ollama('http://h:11434/api/generate', 'm', 'P')
    with pytest.raises(Exception) as e:
        fm.extract_reply(data, 'ollama', seen['url'])
    assert 'http://h:11434/api/generate' in str(e.value)

def test_cli_transport_flags():
    p = fm.build_parser()
    assert p.parse_args(['--survivors', 's', '--out', 'o']).api == 'ollama'
    a = p.parse_args(['--survivors', 's', '--out', 'o', '--api', 'openai', '--url', 'http://h:8080'])
    assert (a.api, a.url) == ('openai', 'http://h:8080')
    assert p.parse_args(['--survivors', 's', '--out', 'o', '--ollama-url', 'http://x/g']).url == 'http://x/g'
