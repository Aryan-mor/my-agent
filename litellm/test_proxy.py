"""Smoke-test the local LiteLLM proxy (127.0.0.1:4000): streaming, tool calls and fallbacks.

Usage:  python test_proxy.py [all|basic|fb|direct|nofb]
Reads LITELLM_MASTER_KEY from the repo-root .env (or MY_AGENT_HOME/.env).
"""
import os, sys, json, time, requests
from pathlib import Path
ROOT = Path(os.environ.get("MY_AGENT_HOME") or Path(__file__).resolve().parents[1])
def loadenv():
    p = ROOT / ".env"
    if not p.exists():
        return
    for l in open(p, encoding="utf-8-sig"):
        l=l.strip()
        if l and not l.startswith("#") and "=" in l:
            k,v=l.split("=",1); v=v.strip().strip("'\"")
            if v: os.environ[k.strip()]=v
loadenv()
H={"Authorization":"Bearer "+os.environ["LITELLM_MASTER_KEY"],"Content-Type":"application/json"}
tools=[{"type":"function","function":{"name":"get_weather","description":"Get weather for a city","parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}}]
def run(model, extra=None, label=""):
    body={"model":model,"stream":True,"messages":[{"role":"user","content":"What's the weather in Berlin? Use the tool."}],"tools":tools,"tool_choice":"auto"}
    if extra: body.update(extra)
    t=time.time()
    r=requests.post("http://127.0.0.1:4000/v1/chat/completions",headers=H,json=body,stream=True,timeout=180)
    used=r.headers.get("x-litellm-model-group"), r.headers.get("x-litellm-model-api-base"), r.headers.get("x-litellm-attempted-fallbacks")
    if r.status_code!=200:
        print(label, model, "HTTP", r.status_code, r.text[:3000]); return
    name=""; args=""; text=""; chunks=0; mdl=None
    for line in r.iter_lines():
        if not line or not line.startswith(b"data: "): continue
        d=line[6:]
        if d==b"[DONE]": break
        j=json.loads(d); chunks+=1; mdl=j.get("model") or mdl
        for c in j.get("choices",[]):
            dl=c.get("delta",{})
            text+=dl.get("content") or ""
            for tc in dl.get("tool_calls") or []:
                f=tc.get("function",{}); name+=f.get("name") or ""; args+=f.get("arguments") or ""
    print(f"{label} req={model} -> model={mdl} group/base/fallbacks={used} chunks={chunks} tool={name!r} args={args!r} text={text[:80]!r} {time.time()-t:.1f}s")
mode=sys.argv[1] if len(sys.argv)>1 else "all"
if mode in("all","basic"):
    run("sonnet",label="[sonnet stream+tool]")
if mode in("all","fb"):
    run("sonnet",{"mock_testing_rate_limit_error":True},label="[sonnet mock 429]")
    run("opus",{"mock_testing_rate_limit_error":True},label="[opus mock 429]")
if mode in("all","direct"):
    for m in ["glm"]:
        run(m,label="[direct]")


if mode=='nofb':
    run('sonnet',{'disable_fallbacks':True},label='[sonnet no-fallback]')
