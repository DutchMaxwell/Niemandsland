#!/usr/bin/env python3
"""Solo-AI review app (goal 003). A tiny Flask server + board viewer for reviewing an AI-vs-AI game on a
phone: swipe through each activation, tap 👍/👎, and the vote is stored server-side (no copy-paste, no
login). Exposed to the phone via a cloudflared quick tunnel. Reads the trace fresh each request, so the
game can be regenerated without restarting.

  TRACE:  tools/review_trace.json   (overwrite to change the game)
  VOTES:  ~/agent-bus/solo-review-votes.jsonl  (one JSON line per vote — the maintainer's feedback)
"""
import json, os, time
from flask import Flask, request, jsonify, Response

HERE = os.path.dirname(os.path.abspath(__file__))
TRACE_PATH = os.path.join(HERE, "review_trace.json")
VOTES_PATH = os.path.expanduser("~/agent-bus/solo-review-votes.jsonl")

app = Flask(__name__)


@app.route("/trace.json")
def trace():
    with open(TRACE_PATH) as f:
        return Response(f.read(), mimetype="application/json")


@app.route("/vote", methods=["POST"])
def vote():
    d = request.get_json(force=True, silent=True) or {}
    rec = {
        "t": round(time.time()),
        "seed": d.get("seed"),
        "step": d.get("step"),
        "verdict": d.get("verdict"),   # "good" | "bad" | null (cleared)
        "unit": d.get("unit"),
        "action": d.get("action"),
        "target": d.get("target"),
        "note": (d.get("note") or "").strip()[:400],
    }
    os.makedirs(os.path.dirname(VOTES_PATH), exist_ok=True)
    with open(VOTES_PATH, "a") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return jsonify(ok=True)


@app.route("/votes")
def votes():
    out = []
    if os.path.exists(VOTES_PATH):
        with open(VOTES_PATH) as f:
            for line in f:
                if line.strip():
                    out.append(json.loads(line))
    return jsonify(out)


@app.route("/")
def index():
    return Response(PAGE, mimetype="text/html")


PAGE = r"""<!doctype html><html lang="de"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Solo-KI Review</title>
<style>
  :root{--bg:#0b0f14;--panel:#121a23;--panel2:#18222d;--line:#28333f;--ink:#e2eaf2;--dim:#8a97a6;
    --faint:#5a6673;--p0:#38c9d6;--p1:#f5a623;--gold:#e8c96a;--wound:#ff5a52;--good:#67d17a;
    --mono:ui-monospace,Menlo,Consolas,monospace;--sans:system-ui,-apple-system,sans-serif}
  *{box-sizing:border-box}
  html,body{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);
    -webkit-font-smoothing:antialiased;overscroll-behavior:none}
  .wrap{max-width:600px;margin:0 auto;padding:10px 12px calc(150px + env(safe-area-inset-bottom))}
  .top{display:flex;align-items:center;gap:8px;font-family:var(--mono);font-size:12px;color:var(--dim);margin-bottom:6px}
  .prog{flex:1;height:5px;background:var(--panel2);border-radius:3px;overflow:hidden}
  .prog>i{display:block;height:100%;background:var(--good);width:0}
  .board{background:var(--panel);border:1px solid var(--line);border-radius:12px;overflow:hidden}
  svg{display:block;width:100%;height:auto}
  .read{background:var(--panel);border:1px solid var(--line);border-radius:12px;margin-top:10px;padding:12px}
  .r1{font-weight:700;font-size:15px}
  .r1 .rd{font-family:var(--mono);font-size:11px;color:var(--faint);text-transform:uppercase;letter-spacing:.06em;margin-right:6px}
  .why{font-family:var(--mono);font-size:12px;color:var(--gold);margin-top:5px}
  .tgt{font-family:var(--mono);font-size:11px;color:var(--dim);margin-top:2px}
  .dice{display:flex;flex-wrap:wrap;gap:4px;margin-top:8px}
  .die{width:24px;height:24px;border-radius:5px;display:grid;place-items:center;font-family:var(--mono);
    font-size:12px;font-weight:700;background:var(--panel2);border:1px solid var(--line);color:var(--dim)}
  .die.hit{background:rgba(103,209,122,.16);border-color:var(--good);color:var(--good)}
  .die.blk{background:rgba(56,201,214,.14);border-color:var(--p0);color:var(--p0)}
  .lbl{font-family:var(--mono);font-size:10px;color:var(--faint);text-transform:uppercase;margin:8px 0 3px}
  .narr{font-family:var(--mono);font-size:12px;color:var(--dim);margin-top:6px}
  /* fixed feedback bar */
  .bar{position:fixed;left:0;right:0;bottom:0;background:linear-gradient(180deg,transparent,var(--bg) 22%);
    padding:14px 12px calc(12px + env(safe-area-inset-bottom));z-index:9}
  .barin{max-width:600px;margin:0 auto;display:flex;flex-direction:column;gap:8px}
  .nav{display:flex;gap:8px}
  .nav button{flex:0 0 auto;width:56px;height:46px;border-radius:10px;border:1px solid var(--line);
    background:var(--panel2);color:var(--ink);font-size:20px;font-family:var(--mono)}
  .nav .ctr{flex:1;display:grid;place-items:center;font-family:var(--mono);font-size:12px;color:var(--dim);
    background:var(--panel);border:1px solid var(--line);border-radius:10px}
  .fb{display:flex;gap:10px}
  .fb button{flex:1;height:56px;border-radius:12px;border:1px solid var(--line);background:var(--panel2);
    color:var(--ink);font-size:17px;font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px}
  .fb .good.on{background:rgba(103,209,122,.2);border-color:var(--good);color:var(--good)}
  .fb .bad.on{background:rgba(255,90,82,.2);border-color:var(--wound);color:var(--wound)}
  button{-webkit-tap-highlight-color:transparent;cursor:pointer}
  button:active{transform:scale(.98)}
  .done{text-align:center;font-family:var(--mono);font-size:12px;color:var(--good);padding:4px}
</style></head><body>
<div class="wrap">
  <div class="top"><span id="match">…</span></div>
  <div class="top"><span id="counter">Schritt –</span><div class="prog"><i id="progbar"></i></div><span id="progtxt"></span></div>
  <div class="board"><svg id="svg" viewBox="0 0 480 480"></svg></div>
  <div class="read" id="read"></div>
</div>
<div class="bar"><div class="barin">
  <div class="nav">
    <button id="prev">◀</button>
    <div class="ctr" id="navctr">–</div>
    <button id="next">▶</button>
  </div>
  <div class="fb">
    <button class="good" id="vgood">👍 gut / regelkonform</button>
    <button class="bad" id="vbad">👎 falsch</button>
  </div>
</div>
<script>
const SVGNS="http://www.w3.org/2000/svg";
let T=null,steps=[],R=[],OBJ=[],ARM={},B=48,SC=10,i=0,votes={};
const $=id=>document.getElementById(id);
function mk(t,a){const e=document.createElementNS(SVGNS,t);for(const k in a)e.setAttribute(k,a[k]);return e;}
fetch('/trace.json').then(r=>r.json()).then(d=>{
  T=d;steps=d.steps;R=d.roster;OBJ=d.objectives;ARM=d.armies;B=d.board;SC=480/B;
  $('match').textContent=`${ARM['0']}  vs  ${ARM['1']}  ·  Seed ${d.seed}`;
  // erste unbewertete Aktivierung
  i=steps.findIndex(s=>s.type==='activation'); if(i<0)i=0;
  render();
});
function board(step){
  const svg=$('svg');while(svg.firstChild)svg.removeChild(svg.firstChild);
  svg.appendChild(mk('rect',{x:0,y:0,width:480,height:480,fill:'#0e1620'}));
  svg.appendChild(mk('rect',{x:0,y:0,width:480,height:12*SC,fill:'#38c9d6',opacity:.06}));
  svg.appendChild(mk('rect',{x:0,y:480-12*SC,width:480,height:12*SC,fill:'#f5a623',opacity:.06}));
  for(let g=12;g<B;g+=12){svg.appendChild(mk('line',{x1:g*SC,y1:0,x2:g*SC,y2:480,stroke:'#1c2733','stroke-width':1}));
    svg.appendChild(mk('line',{x1:0,y1:g*SC,x2:480,y2:g*SC,stroke:'#1c2733','stroke-width':1}));}
  const bd=step.board,own=bd.owners;
  OBJ.forEach((o,ix)=>{const cx=o[0]*SC,cy=o[1]*SC,ow=own[ix],c=ow===0?'#38c9d6':(ow===1?'#f5a623':'#e8c96a');
    svg.appendChild(mk('circle',{cx,cy,r:3*SC,fill:'none',stroke:c,'stroke-dasharray':'3 3',opacity:.5}));
    const g=mk('rect',{x:cx-7,y:cy-7,width:14,height:14,transform:`rotate(45 ${cx} ${cy})`,fill:ow<0?'none':c,stroke:c,'stroke-width':2});svg.appendChild(g);});
  const act=step.type==='activation'?step.unit_id:-1,tgt=step.type==='activation'?(step.target_id):-2;
  bd.pos.forEach((p,id)=>{const al=bd.alive[id],info=R[id],cx=p[0]*SC,cy=p[1]*SC,c=info.player===0?'#38c9d6':'#f5a623';
    if(al<=0){const x=mk('g',{opacity:.35});x.appendChild(mk('line',{x1:cx-5,y1:cy-5,x2:cx+5,y2:cy+5,stroke:c,'stroke-width':2}));x.appendChild(mk('line',{x1:cx-5,y1:cy+5,x2:cx+5,y2:cy-5,stroke:c,'stroke-width':2}));svg.appendChild(x);return;}
    const cols=Math.ceil(Math.sqrt(al)),rows=Math.ceil(al/cols),sp=6,w=(cols-1)*sp,h=(rows-1)*sp,rr=Math.max(w,h)/2+8;
    if(id===act)svg.appendChild(mk('circle',{cx,cy,r:rr,fill:'none',stroke:'#fff','stroke-width':1.5}));
    if(id===tgt)svg.appendChild(mk('circle',{cx,cy,r:rr,fill:'none',stroke:'#ff5a52','stroke-width':1.5,'stroke-dasharray':'4 3'}));
    for(let k=0;k<al;k++){svg.appendChild(mk('circle',{cx:cx+(k%cols)*sp-w/2,cy:cy+Math.floor(k/cols)*sp-h/2,r:2.4,fill:c,opacity:bd.shaken[id]?.4:.95}));}
    const t=mk('text',{x:cx,y:cy+rr+9,'text-anchor':'middle','font-size':8,fill:c,'font-family':'monospace',opacity:.85});t.textContent=al;svg.appendChild(t);
    if(bd.shaken[id]){const s=mk('text',{x:cx,y:cy-rr-3,'text-anchor':'middle','font-size':8,fill:'#38c9d6','font-family':'monospace'});s.textContent='SHAKEN';svg.appendChild(s);}
  });
}
const die=(n,cl)=>`<div class="die ${cl}">${n<0?'—':n}</div>`;
const hd=(f,t)=>f.map(x=>die(x,(x===6||(x>=t&&x!==1))?'hit':'')).join('');
const sd=(f,t)=>f.map(x=>die(x,(x===6||(x>=t&&x!==1))?'blk':'')).join('');
function read(step){
  const el=$('read');
  if(step.type==='deploy'){el.innerHTML='<div class="r1"><span class="rd">Aufstellung</span></div><div class="narr">Beide Armeen in ihren 12"-Zonen; zwei Missionsziele.</div>';return;}
  if(step.type==='seize'){const o=step.board.owners.map((v,ix)=>`Ziel ${ix+1}: ${v===0?ARM['0']:(v===1?ARM['1']:'neutral')}`).join(' · ');
    el.innerHTML=`<div class="r1"><span class="rd">Rundenende ${step.round}</span></div><div class="why">${o}</div>`;return;}
  const wy=step.why||{},arch={MELEE:'Nahkämpfer',SHOOTING:'Schütze',HYBRID:'Hybrid'}[wy.arch]||'?';
  let dec;
  if(wy.toward==='objective')dec=`zieht zum Missionsziel (${wy.obj_dist}")`+(step.action.indexOf('shoot')>=0?' und schießt':'');
  else if(step.action.indexOf('charge')>=0)dec=`chargt ${step.target}`;
  else if(wy.range>0)dec=`schießt (bleibt auf ${wy.range}" Reichweite)`;
  else dec=`rückt zum Nahkampf vor`;
  let h=`<div class="r1"><span class="rd">Runde ${step.round}</span>${step.unit} <span style="color:${step.player===0?'#38c9d6':'#f5a623'}">(${arch})</span></div>`;
  h+=`<div class="why">▸ ${dec}</div>`;
  if(step.target)h+=`<div class="tgt">Ziel: ${step.target}${wy.target_fresh?' · noch nicht aktiviert ✓':' · schon aktiviert'}</div>`;
  (step.rolls||[]).forEach(r=>{
    if(r.kind==='morale'){const res=r.result==='pass'?'bestanden':(r.result==='shaken'?'→ Shaken':'→ ROUT');
      h+=`<div class="lbl">Moral</div><div class="dice">${r.face<0?'<span class="narr">auto-fail (Shaken)</span>':die(r.face,r.result==='pass'?'hit':'blk')}<span class="narr" style="margin-left:8px">${res}</span></div>`;
    }else{const v=r.kind==='shoot'?'Beschuss':(r.kind==='strike back'?'Rückschlag':'Nahkampf');
      h+=`<div class="lbl">${v} · ${r.weapon} → ${r.wounds} Wunde(n)</div><div class="dice">${hd(r.hit_faces,r.hit_target)}</div>`;
      if(r.hits>0)h+=`<div class="lbl">Rettung ${r.save_target}+</div><div class="dice">${sd(r.save_faces,r.save_target)}</div>`;}
  });
  if((step.rolls||[]).length===0&&step.action.indexOf('IDLE')<0)h+=`<div class="narr">◦ nur Bewegung — keine Würfel.</div>`;
  el.innerHTML=h;
}
function updateFB(){
  const step=steps[i],isAct=step&&step.type==='activation',v=votes[i];
  $('vgood').classList.toggle('on',v==='good');$('vbad').classList.toggle('on',v==='bad');
  $('vgood').style.opacity=isAct?1:.4;$('vbad').style.opacity=isAct?1:.4;
  const rated=Object.values(votes).filter(Boolean).length;
  const total=steps.filter(s=>s.type==='activation').length;
  $('progbar').style.width=(100*rated/total)+'%';$('progtxt').textContent=`${rated}/${total}`;
  $('navctr').textContent=`${i+1} / ${steps.length}`;
}
function render(){board(steps[i]);read(steps[i]);updateFB();window.scrollTo(0,0);}
function go(n){i=Math.max(0,Math.min(steps.length-1,n));render();}
function sendVote(step,val){
  fetch('/vote',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({
    seed:T.seed,step:i,verdict:val,unit:step.unit,action:step.action,target:step.target})}).catch(()=>{});
}
function vote(val){
  const step=steps[i]; if(step.type!=='activation')return;
  votes[i]=(votes[i]===val)?null:val; sendVote(step,votes[i]);
  updateFB();
  if(votes[i]){ // auto-advance to next unrated activation
    let j=i+1; while(j<steps.length&&(steps[j].type!=='activation'||votes[j]))j++;
    if(j<steps.length){go(j);return;}
  }
}
$('prev').onclick=()=>go(i-1);$('next').onclick=()=>go(i+1);
$('vgood').onclick=()=>vote('good');$('vbad').onclick=()=>vote('bad');
</script></body></html>"""


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8770"))
    app.run(host="127.0.0.1", port=port)
