"""Package real Godot event captures as an offline review gallery and contact sheets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]

# Observations from this capture batch, kept separate from wiring failures.
VISUAL_NOTES = {
    "ink_pool": "旧版水墨插画：细节密度、灰褐色调与后续彩色插画不同，建议先确认是否统一重绘。",
    "broken_stele": "旧版水墨插画：细节密度、灰褐色调与后续彩色插画不同，建议先确认是否统一重绘。",
    "old_bookshop": "旧版水墨插画：细节密度、灰褐色调与后续彩色插画不同，建议先确认是否统一重绘。",
    "lantern_pages": "主体背后保留大块黑色斜边，和其他插画的独立场景底座不一致，需审查轮廓是否合适。",
    "kite_in_tree": "当前图以纸鸢和飘带为主，未明确表现文案中的树枝；需确认叙事主体是否足够。",
    "ferry_no_boat": "浅色六边形背景非常醒目，和大部分插画的透明外缘不一致。",
    "jade_case": "当前主体更像带屋顶的小亭，文案强调的是玉匣；入口及四张后续文本页都沿用此图，建议优先核对。",
    "carry_jade": "当前主体是一块较暗的小布包，画面占比偏小；手机上需重点审查主体辨识度。",
}


def font(size: int):
    for path in [Path("C:/Windows/Fonts/msyh.ttc"), Path("C:/Windows/Fonts/simhei.ttf")]:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)


def sheets(folder: Path, entries: list[dict], profile: str) -> list[str]:
    result = []
    for offset in range(0, len(entries), 12):
        group = entries[offset:offset+12]
        thumb_w, thumb_h = 600, 338 if profile == "desktop" else 278
        cell_w, cell_h = 624, thumb_h+74
        canvas = Image.new("RGB", (cell_w*3+24, ((len(group)+2)//3)*cell_h+86), "#101e24")
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 15), f"炼字狱 · 事件实机预览 / {'电脑 1280×720' if profile=='desktop' else '手机横屏 844×390'} · {offset//12+1}", font=font(27), fill="#eee0bb")
        for index, entry in enumerate(group):
            x, y = 12+(index%3)*cell_w, 76+(index//3)*cell_h
            capture = entry["captures"][profile]
            source = Image.open(folder/capture["screenshot"]).convert("RGB")
            fitted = ImageOps.contain(source, (thumb_w, thumb_h), Image.Resampling.LANCZOS)
            canvas.paste(fitted, (x+(thumb_w-fitted.width)//2, y+(thumb_h-fitted.height)//2))
            name = f"{entry['number']:02d} {entry['title']}" + (f" / {entry['node']}" if entry["node"]!="start" else "")
            draw.text((x, y+thumb_h+5), name, font=font(21), fill="#eee0bb")
            draw.text((x, y+thumb_h+33), f"{entry['id']} · {'需核对' if entry['issues'] else '路径匹配'}", font=font(16), fill="#b6c8c4")
        path = f"sheets/{profile}-{offset//12+1:02d}.jpg"
        canvas.save(folder/path, quality=94, subsampling=0)
        result.append(path)
    return result


def asset_sheet(folder: Path, entries: list[dict]) -> str:
    roots = [e for e in entries if e["node"]=="start"]
    canvas = Image.new("RGB", (1660, ((len(roots)+4)//5)*276+76), "#101e24")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 16), "炼字狱 · 已接入原图总览（非游戏截图）", font=font(28), fill="#eee0bb")
    for i, entry in enumerate(roots):
        x, y = 14+(i%5)*330, 72+(i//5)*276
        image = Image.open(folder/entry["asset_preview"]).convert("RGBA")
        image.thumbnail((306, 220), Image.Resampling.LANCZOS)
        draw.rectangle((x, y, x+306, y+220), fill="#b9b0a0")
        canvas.paste(image, (x+(306-image.width)//2, y+(220-image.height)//2), image)
        draw.text((x, y+223), f"{entry['number']:02d} {entry['title']}", font=font(19), fill="#eee0bb")
        draw.text((x, y+248), entry["id"], font=font(14), fill="#b6c8c4")
    path = "sheets/source-assets.jpg"
    canvas.save(folder/path, quality=94, subsampling=0)
    return path


HTML = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>炼字狱 · 事件美术审查</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#111b20;color:#e8e1d2;font:15px/1.5 system-ui,"Microsoft YaHei",sans-serif}button,input,select,textarea{font:inherit;color:inherit;background:#24343b;border:1px solid #526168;border-radius:5px;padding:9px 12px}button{cursor:pointer;min-height:42px}button:hover{border-color:#d6b46c}input{min-width:230px}header{position:sticky;top:0;background:#142329f5;padding:20px 28px;z-index:3;border-bottom:1px solid #445259}h1{font-size:25px;margin:0 0 7px}h2{font-size:20px;margin:0 0 12px}.muted{color:#acb8bb}.tools{display:flex;gap:12px;align-items:center;flex-wrap:wrap;margin-top:14px}.tools label{display:flex;align-items:center;gap:6px}.tools label input{min-width:unset}.notice{padding:15px 28px;background:#253136;color:#ccdadb}.grid{padding:24px;display:grid;grid-template-columns:repeat(auto-fill,minmax(370px,1fr));gap:20px}.card{border:1px solid #3d515a;background:#19282e;border-radius:7px;overflow:hidden}.card>button{display:block;width:100%;padding:0;border:0;border-radius:0;background:#0d161a}.card img{display:block;width:100%;height:auto}.caption{padding:14px}.line{display:flex;gap:9px;align-items:center;justify-content:space-between}.badge{font-size:12px;color:#b8ded0;border:1px solid #44695e;border-radius:20px;padding:2px 8px;white-space:nowrap}.badge.warn{color:#f0bd9a;border-color:#aa7456}.path{overflow-wrap:anywhere;font:12px/1.6 ui-monospace,monospace;color:#aabec4;margin-top:7px}.modal{position:fixed;inset:0;z-index:10;background:#071015ee;overflow:auto;padding:22px;display:none}.modal.open{display:block}.dialog{max-width:1800px;margin:auto;background:#142329;border:1px solid #617179;border-radius:7px}.dialog-head{position:sticky;top:-22px;z-index:2;background:#142329f5;padding:14px 18px;display:flex;align-items:center;gap:12px;border-bottom:1px solid #435963}.dialog-head strong{flex:1}.body{display:grid;grid-template-columns:minmax(0,1fr) 330px;gap:20px;padding:18px}.canvas{position:relative;width:100%;height:fit-content;background:#0d161a}.canvas>img{width:100%;display:block}.region{position:absolute;pointer-events:none;border:2px dashed #e3b45e;display:none}.region.real{border-color:#64ccec;border-style:solid}.region span{position:absolute;top:0;left:0;background:#13232ded;color:#e4e7e0;font-size:12px;padding:1px 4px;white-space:nowrap}.boxes .region{display:block}aside{font-size:14px}aside h3{margin:14px 0 5px}.source{width:100%;max-height:280px;object-fit:contain;background:repeating-conic-gradient(#aaa399 0 25%,#d2c8b6 0 50%) 0/20px 20px;border:1px solid #647078}.story{white-space:pre-wrap;color:#b9c9cb;font-size:13px}textarea{width:100%;min-height:100px;resize:vertical;margin-top:8px}a{color:#b6dcdf}#empty{padding:30px;display:none}.foot{padding:0 28px 25px;font-size:13px;color:#9aacb3}.links{display:flex;gap:15px;flex-wrap:wrap}#count{font-size:13px}#bottom{display:none}@media(max-width:800px){header{padding:15px}.grid{padding:12px;grid-template-columns:1fr}.body{grid-template-columns:1fr}.modal{padding:8px}.dialog-head{top:-8px}}
</style>
<header><h1>炼字狱 · 事件美术审查</h1><div class="muted" id="summary"></div>
<div class="tools"><input id="search" placeholder="搜索名称、事件 ID 或图片路径" aria-label="搜索事件">
<select id="profile" aria-label="预览尺寸"><option value="desktop">电脑 1280×720</option><option value="phone">手机横屏 844×390</option></select>
<select id="filter" aria-label="图片状态"><option value="all">全部接线</option><option value="visual">有视检提示</option><option value="issues">接线异常</option><option value="ink">旧版墨色插图</option><option value="scene">新版场景插图</option></select>
<label><input type="checkbox" id="branches" checked>包含后续文本页</label><label><input type="checkbox" id="bounds">显示插画边界</label><button id="export">导出审查意见</button><span id="count"></span></div></header>
<div class="notice">所有画面均由当前 Godot 事件页实际渲染。点击任意一张，核对原图、实际路径和位置，并填写意见。黄色虚线为插画控件，蓝色实线为完整图片绘制范围（含源图透明留白）。意见保存在本浏览器中，可导出 JSON。</div>
<main id="grid" class="grid"></main><div id="empty">没有匹配的页面。</div>
<footer class="foot"><div class="links"><a href="审查索引.md">完整接线索引及视检提示</a><a href="capture.json">运行时采集数据</a><a href="sheets/source-assets.jpg">原图总览</a></div><p>路径一致表示运行时加载与配置相符，不代表图意或美术质量已通过。手机预览来自桌面渲染器的横屏尺寸模拟。本批核对图片、图文布局和目录文本节点，未逐个结算选项。</p></footer>
<section id="modal" class="modal" role="dialog" aria-modal="true" aria-label="事件详情"><div class="dialog"><div class="dialog-head"><button id="prev">上一页</button><strong id="heading"></strong><button id="next">下一页</button><button id="close">关闭</button></div><div class="body"><div><div id="canvas" class="canvas"><img id="screen" alt="实际游戏事件页"><div id="slot" class="region"><span>插画控件</span></div><div id="imagebox" class="region real"><span>完整图片</span></div></div><p><a id="full" target="_blank">打开原尺寸实机图</a>　<a id="bottom" target="_blank">查看滚动到底</a></p></div><aside><img id="source" class="source" alt="实际加载的源图"><h3>接线</h3><div id="paths" class="path"></div><div id="issues" class="story"></div><h3>审查意见</h3><select id="decision"><option value="待审">待审</option><option value="通过">通过</option><option value="换图">需要换图</option><option value="位置调整">位置需要调整</option><option value="待讨论">待讨论</option></select><textarea id="note" placeholder="例如：主体太靠边／图与事件不符／希望放大……" aria-label="审查意见"></textarea><h3>当前文本节点</h3><div id="story" class="story"></div></aside></div></div></section>
<script>
const DATA=__DATA_JSON__, $=id=>document.getElementById(id), KEY='lianziyu-event-art-review-20261020';let notes={},visible=[],active=null;
try{notes=JSON.parse(localStorage.getItem(KEY)||'{}')}catch(e){}
function identity(e){return e.id+'/'+e.node}function decision(e){return (notes[identity(e)]||{}).decision||'待审'}
$('summary').textContent=`${DATA.event_count} 个事件 · ${DATA.page_count} 个文本页面 · ${DATA.entries.filter(e=>!e.issues.length).length} 页路径及区域检查正常 · ${DATA.captured_at}`;
function render(){let q=$('search').value.trim().toLowerCase(),filter=$('filter').value,p=$('profile').value;
 visible=DATA.entries.filter(e=>($('branches').checked||e.node==='start')&&(!q||[e.title,e.id,e.node,e.runtime_path].join(' ').toLowerCase().includes(q))&&(filter==='all'||filter==='visual'&&e.visual_notes.length||filter==='issues'&&e.issues.length||filter===e.style));
 $('grid').replaceChildren();for(const e of visible){let c=document.createElement('article');c.className='card';let b=document.createElement('button'),im=document.createElement('img');im.src=e.captures[p].screenshot;im.alt=e.title+' 实机预览';im.loading='lazy';b.append(im);b.onclick=()=>open(e);c.append(b);
 let cap=document.createElement('div');cap.className='caption';let line=document.createElement('div');line.className='line';let title=document.createElement('strong');title.textContent=String(e.number).padStart(2,'0')+' '+e.title+(e.node==='start'?'':' / '+e.node);let tag=document.createElement('span');tag.className='badge'+(e.issues.length?' warn':'');tag.textContent=e.issues.length?'需核对':decision(e)==='待审'?'接线一致':decision(e);line.append(title,tag);cap.append(line);
 let path=document.createElement('div');path.className='path';path.textContent=e.id+' · '+e.runtime_path;cap.append(path);if(e.visual_notes.length){let n=document.createElement('div');n.style.color='#e5c28a';n.style.fontSize='13px';n.style.marginTop='7px';n.textContent='视检提示：'+e.visual_notes.join('；');cap.append(n)}c.append(cap);$('grid').append(c)}
 $('count').textContent=`显示 ${visible.length} 页 · 已记录 ${Object.keys(notes).length} 页意见`;$('empty').style.display=visible.length?'none':'block';if(active)paint(active)}
function rect(el,a,cap){el.style.left=100*a[0]/cap.viewport[0]+'%';el.style.top=100*a[1]/cap.viewport[1]+'%';el.style.width=100*a[2]/cap.viewport[0]+'%';el.style.height=100*a[3]/cap.viewport[1]+'%'}
function paint(e){let cap=e.captures[$('profile').value];$('heading').textContent=String(e.number).padStart(2,'0')+' '+e.title+' / '+e.node;$('screen').src=cap.screenshot;$('full').href=cap.screenshot;$('source').src=e.asset_preview;$('canvas').classList.toggle('boxes',$('bounds').checked);rect($('slot'),cap.art_rect,cap);rect($('imagebox'),cap.image_rect,cap);$('paths').textContent='实际加载：'+e.runtime_path+'\n目录配置：'+(e.configured_path||'未指定')+'\n清单配置：'+(e.manifest_path||'未指定')+'\n源图：'+e.source_dimensions.join(' × ')+' / '+e.style;$('paths').style.whiteSpace='pre-wrap';$('issues').textContent=e.issues.length?e.issues.join('\n'):'路径匹配；插画控件位于首屏，未与文字区域重叠。';$('story').textContent=e.body+'\n\n'+e.options.map((t,i)=>(i+1)+'. '+t).join('\n');$('decision').value=decision(e);$('note').value=(notes[identity(e)]||{}).note||'';$('bottom').style.display=cap.bottom_screenshot?'inline':'none';if(cap.bottom_screenshot)$('bottom').href=cap.bottom_screenshot}
function open(e){active=e;paint(e);$('modal').classList.add('open');document.body.style.overflow='hidden';$('close').focus()}function close(){$('modal').classList.remove('open');document.body.style.overflow='';active=null}
function save(){if(!active)return;notes[identity(active)]={number:active.number,id:active.id,node:active.node,title:active.title,path:active.runtime_path,decision:$('decision').value,note:$('note').value};try{localStorage.setItem(KEY,JSON.stringify(notes))}catch(e){}$('count').textContent=`显示 ${visible.length} 页 · 已记录 ${Object.keys(notes).length} 页意见`}
for(let id of ['search','profile','filter','branches','bounds'])$(id).addEventListener(id==='search'?'input':'change',render);$('decision').onchange=save;$('note').oninput=save;$('close').onclick=()=>{close();render()};$('modal').onclick=e=>{if(e.target===$('modal')){close();render()}};
function step(delta){if(!visible.length)return;let index=visible.indexOf(active);open(visible[(index+delta+visible.length)%visible.length])}$('prev').onclick=()=>step(-1);$('next').onclick=()=>step(1);
document.addEventListener('keydown',e=>{if(!active||['TEXTAREA','INPUT','SELECT'].includes(document.activeElement.tagName))return;if(e.key==='Escape'){close();render()}if(e.key==='ArrowLeft')step(-1);if(e.key==='ArrowRight')step(1)});
$('export').onclick=()=>{let blob=new Blob([JSON.stringify({capture:DATA.captured_at,source_hashes:DATA.source_hashes,notes:Object.values(notes)},null,2)],{type:'application/json'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='炼字狱-事件美术审查意见.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)};render();
</script></html>'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", nargs="?", default="docs/qa/event-art-review-2026-10-20")
    args = parser.parse_args()
    folder = (ROOT/args.folder).resolve()
    report = json.loads((folder/"capture.json").read_text(encoding="utf-8"))
    (folder/"sources").mkdir(exist_ok=True)
    (folder/"sheets").mkdir(exist_ok=True)
    for entry in report["entries"]:
        entry["visual_notes"] = [VISUAL_NOTES[entry["id"]]] if entry["id"] in VISUAL_NOTES else []
        source = ROOT/entry["runtime_path"].removeprefix("res://")
        if not source.is_file():
            raise RuntimeError(f"Missing runtime source: {source}")
        image = Image.open(source).convert("RGBA")
        entry["source_dimensions"] = list(image.size)
        entry["source_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
        entry["asset_preview"] = f"sources/{entry['id']}.png"
        image.thumbnail((640,640),Image.Resampling.LANCZOS)
        image.save(folder/entry["asset_preview"])
        for capture in entry["captures"].values():
            image = Image.open(folder/capture["screenshot"])
            if list(image.size)!=capture["viewport"]:
                raise RuntimeError("Capture dimensions disagree with runtime metadata")
    report["contact_sheets"] = {profile:sheets(folder,report["entries"],profile) for profile in ["desktop","phone"]}
    report["asset_sheet"] = asset_sheet(folder,report["entries"])
    data = json.dumps(report,ensure_ascii=False).replace("<","\\u003c")
    (folder/"index.html").write_text(HTML.replace("__DATA_JSON__",data),encoding="utf-8")
    (folder/"review-data.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    lines = ["# 炼字狱 · 事件美术审查", "", f"本批由当前 Godot 生产事件页渲染：{report['event_count']} 个事件，{report['page_count']} 个文本页面，每页包含电脑和手机横屏两种尺寸。", "", f"[交互审查总览]({(folder/'index.html').as_posix()})", "", "每页包含实际加载路径、目录与清单来源，以及原图对照。黄色虚线表示插画控件，蓝线表示完整图片绘制范围，透明留白属于源图。", "", "| 编号 | 事件 / 节点 | 电脑 | 手机横屏 | 接线 |", "| --- | --- | --- | --- | --- |"]
    for e in report["entries"]:
        lines.append(f"| {e['number']:02d} | {e['title']} / {e['node']} | [查看]({(folder/e['captures']['desktop']['screenshot']).as_posix()}) | [查看]({(folder/e['captures']['phone']['screenshot']).as_posix()}) | {'；'.join(e['issues']) or '路径一致'} |")
    lines += ["", "## 优先审查的视觉差异", "", "以下为本批截图的视检提示，保留原样供审，不作为自动接线错误判定。", ""]
    for e in report["entries"]:
        if e["node"]=="start" and e["visual_notes"]:
            lines.append(f"- {e['number']:02d} **{e['title']}**：{'；'.join(e['visual_notes'])} [实机图]({(folder/e['captures']['desktop']['screenshot']).as_posix()})")
    lines += ["", "固定预览条件：气血 45/60、铜钱 60、寿债数值 8；条件不满足的选项可能置灰，不代表按钮未接线。无字灯、射覆使用固定预览种子。只预览，不结算任何选项，不改动用户存档。", "", "核验范围：运行时图片路径、图片是否显示、插画与文案区域位置，以及当前目录的全部文本节点。路径一致表示加载与配置相符，不表示图意与美术质量已通过。手机来自桌面渲染器模拟；不据截图认定结算、触控或无障碍完全通过。"]
    (folder/"审查索引.md").write_text("\n".join(lines)+"\n",encoding="utf-8")
    with zipfile.ZipFile(folder.parent/(folder.name+".zip"),"w",compression=zipfile.ZIP_DEFLATED,compresslevel=4) as package:
        for path in sorted(folder.rglob("*")):
            if path.is_file() and path.name!=".gdignore":
                package.write(path,path.relative_to(folder))
    print(json.dumps({"events":report["event_count"],"pages":report["page_count"],"issues":sum(bool(e["issues"]) for e in report["entries"]),"gallery":str(folder/"index.html"),"sheets":report["contact_sheets"]},ensure_ascii=False))


if __name__=="__main__":
    main()
