#!/usr/bin/env python3
"""分档测试运行器：只跑和本次改动相关的套件，重测试默认不跑。

用法：
    python tools/run_tests.py --list                 # 列出分组与重测试
    python tools/run_tests.py --changed               # 按 git 改动自动选组（日常用这个）
    python tools/run_tests.py --group core            # 只跑某一组
    python tools/run_tests.py --group core,relic      # 跑多组
    python tools/run_tests.py logic_test relic_test   # 只跑指定套件
    python tools/run_tests.py --group core --all      # 含重测试
    python tools/run_tests.py --group art --all --timeout 1800

约定：
- `core` / `relic` / `event` / `economy` / `battleui` / `map` 是常规组；
- `art` / `layout` 是重测试组（成套渲染、逐尺寸布局），只在显式 `--all` 或指定组名时跑；
- 单个套件超时会记为 TIMEOUT 并继续（避免一个挂死拖住整轮）。
"""
from __future__ import annotations

import argparse
import os
import queue
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"

# ---------------------------------------------------------------- 分组

CORE = [
    "logic_test",
    "word_effect_regression",
    "effect_help_test",
    "battle_balance_test",
    "special_glyph_test",
    "passive_stacking_test",
    "repeated_row_target_test",
    "interest_damage_test",
    "xuanji_board_test",
    "enemy_balance_test",
    "enemy_injection_test",
    "encounter_balance_test",
    "encounter_variety_test",
    "jialiu_word_test",
    "effect_contract_test",
    "player_copy_test",
]

RELIC = [
    "relic_test",
    "relic_audit_test",
    "relic_batch2_test",
    "relic_compendium_test",
    "relic_edge_test",
    "relic_expansion_test",
    "classic_relic_test",
    "debug_relic_test",
]

EVENT = [
    "event_system_test",
    "event_interaction_test",
    "event_reward_audit_test",
    "room_event_ui_test",
]

# 引用了已删除接口 / 已写死旧实现的测试：默认不跑，显式点名才跑（会提示原因）。
STALE = {
    "expedition_map_view_test": "行囊面板已改为 RunInventory 覆盖层，脚本仍断言已删除的 _actor_panel；待按新布局重写",
}

ECONOMY = [
    "economy_gild_test",
    "shop_actions_test",
    "shop_refresh_test",
    "buy_picker_scroll_test",
    "run_settlement_test",
    "defeat_settlement_test",
    "unified_result_test",
    "run_inventory_test",
    "autosave_test",
    "room_reward_test",
    "reward_loot_3d_test",
]

BATTLE_UI = [
    "battle_ui_test",
    "battle_entrance_test",
    "battle_help_layout_test",
    "battle_pile_ui_test",
    "hud_stability_test",
    "active_status_hud_test",
    "intent_design_test",
    "modifier_display_test",
    "recent_log_test",
    "header_overlay_test",
    "frontend_cleanup_test",
    "frontend_feedback_test",
    "journey_ui_test",
    "title_menu_test",
    "title_branding_runtime",
    "motion_settings_test",
    "first_run_tutorial_test",
    "tutorial_interaction_test",
    "tutorial_spotlight_test",
    "study_flow_test",
]

MAP = [
    "expedition_test",
    "expedition_options_test",
    "expedition_relic_loot_test",
    "expedition_growth_test",
    "expedition_map_view_test",
    "expedition_act_exit_test",
    "node_route_test",
    "node_route_generation_test",
    "room_route_test",
]

# 重测试：成套渲染、逐尺寸布局、逐动画检查。默认不跑。
HEAVY_ART = [
    "art_design_merge_test",
    "battle_art_entry_test",
    "battle_presentation_regression",
    "battle_description_audit_test",
    "enemy_art_completion_test",
    "enemy_attack_animation_test",
    "fold_page_moth_animation_test",
    "guardian_animation_test",
    "needle_wasp_animation_test",
    "paper_shell_animation_test",
    "tilting_inkstone_animation_test",
    "glyph_vfx_test",
    "glyph_graph_test",
    "glyph_graph_interaction_test",
    "object_stage_test",
    "relic_art_test",
    "taopunk_art_test",
    "room_art_assets_test",
    "event_art_test",
    "event_illustration_sample",
    "expedition_render_regression",
    "expedition_terrain_gallery",
    "music_test",
    "menu_return_performance_test",
]

HEAVY_LAYOUT = [
    "mobile_layout_matrix",
    "mobile_density_layout_test",
    "mobile_presentation_fix_test",
    "ui_resolution_matrix",
    "battle_responsive_layout_test",
    "touch_access_audit_test",
    "status_intent_fix_test",
    "tooltip_ui_test",
    "ui_consistency_test",
]

# 只改文案时跑这一组（约 6 秒）：可读性、术语链接、说明与 WORDS 同步
COPY = ["player_copy_test", "effect_help_test"]

GROUPS = {
    "copy": COPY,
    "core": CORE,
    "relic": RELIC,
    "event": EVENT,
    "economy": ECONOMY,
    "battleui": BATTLE_UI,
    "map": MAP,
    "art": HEAVY_ART,
    "layout": HEAVY_LAYOUT,
}
HEAVY_GROUPS = {"map", "art", "layout"}
CHANGED_SKIP = HEAVY_GROUPS | {"economy", "battleui"}

# ---------------------------------------------------------------- 改动 → 分组

# 前缀匹配，命中第一条即止。刻意偏保守：不确定时多跑 core。
RULES = [
    ("src/core/relics.gd", ["relic", "core"]),
    ("src/core/battle_state.gd", ["core", "relic"]),
    ("src/core/effect_", ["core"]),
    ("src/core/combatant.gd", ["core"]),
    ("src/core/battle_ops.gd", ["core"]),
    ("src/core/battle_balance.gd", ["core"]),
    ("resources/characters/", ["copy"]),
    ("resources/words/", ["copy"]),
    ("src/data/battle_text.gd", ["copy"]),
    ("src/data/word_descriptions.gd", ["copy"]),
    ("src/data/event_catalog.gd", ["copy"]),
    ("resources/statuses/", ["core"]),
    ("resources/pollutions/", ["core"]),
    ("resources/enemies/", ["core", "map"]),
    ("data/balance/", ["core", "relic"]),
    ("src/data/event_effects.gd", ["event", "copy"]),
    ("src/screens/event_screen.gd", ["event"]),
    ("src/screens/shop_screen.gd", ["economy"]),
    ("src/screens/reward_screen.gd", ["economy"]),
    ("src/screens/rest_screen.gd", ["economy"]),
    ("src/core/run_harness.gd", ["economy", "core"]),
    ("src/expedition/", ["map"]),
    ("src/map/", ["map"]),
    ("src/screens/room_map_screen.gd", ["map"]),
    ("src/screens/expedition_map_screen.gd", ["map"]),
    ("src/battle/", ["art", "battleui"]),
    ("src/board/", ["battleui"]),
    ("src/screens/battle_screen.gd", ["battleui"]),
    ("src/ui/", ["battleui"]),
    ("assets/", ["art"]),
]

DEFAULT_GROUPS = ["core"]

# 仓库当前基线就是红的套件：默认标 KNOWN-RED，不计入失败；--strict 时按失败算。
# 每次改动后请顺手复核这张表，修好了就把对应行删掉。
KNOWN_RED = {
    "effect_contract_test": "基线红：效果契约（3 条）",
    "recent_log_test": "基线红：战报布局（4 条）",
    "intent_design_test": "基线红：意图文案（6 条）",
    "battle_ui_test": "基线红：AchievementArt 未注册导致 1 条",
    "relic_expansion_test": "基线红：旧 PNG 字节一致（1 条）",
    "expedition_relic_loot_test": "基线红：遗物长说明布局（2 条）",
    "classic_relic_test": "基线红且随机波动（2~4 条）",
    "header_overlay_test": "断言全过（88），退出时 ObjectDB 泄漏导致 ERROR",
    "journey_ui_test": "基线红：GameStyle.paper() 已随样式合并移除，脚本未更新",
    "debug_relic_test": "基线红：遗物自检（26 条）",
    "battle_help_layout_test": "基线红：帮助文本刷新边界（1 条）",
}

# ---------------------------------------------------------------- 运行

PASS_RE = re.compile(r"PASS=(\d+)\s+FAIL=(\d+)")
CHECKS_RE = re.compile(r"CHECKS=(\d+)\s+FAIL=(\d+)")
LOWER_RE = re.compile(r"checks=(\d+)\s+failures=(\[([^\]]*)\]|(\d+))")
FATAL_RE = re.compile(r"^(?:SCRIPT ERROR:|ERROR: Failed to (?:load script|instantiate|open))", re.MULTILINE)
LOG_DIR = ROOT / "shots" / "test-runs" / str(os.getpid())


def find_godot(explicit: str | None) -> Path:
    candidates = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("GODOT_BIN"):
        candidates.append(os.environ["GODOT_BIN"])
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            candidates.append(found)
    candidates += [
        r"D:/Apps/Godot/Godot_v4.7.2-stable_win64.exe",
        r"D:/Apps/Godot/Godot_v4.7.2-stable_win64_console.exe",
        r"C:/Program Files/Godot/Godot_v4.7.2-stable_win64.exe",
    ]
    for c in candidates:
        p = Path(c)
        if p.is_file():
            return p
    sys.exit("找不到 Godot 可执行文件：请用 --godot 指定，或设置 GODOT_BIN")


def changed_groups() -> list[str]:
    try:
        out = subprocess.run(
            ["git", "-C", str(ROOT), "status", "--porcelain"],
            capture_output=True, text=True, check=True,
        ).stdout
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] 读取 git 状态失败（{exc}），退回 core")
        return list(DEFAULT_GROUPS)
    paths = []
    for line in out.splitlines():
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.split(" -> ", 1)[1]
        paths.append(path.replace("\\", "/"))
    if not paths:
        print("[info] 工作区没有改动，默认跑 core")
        return list(DEFAULT_GROUPS)
    groups: list[str] = []
    for path in paths:
        hit = None
        for prefix, mapped in RULES:
            if path.startswith(prefix):
                hit = mapped
                break
        if hit is None and path.startswith("tests/") and path.endswith(".gd"):
            # 改的是某个套件自己：直接跑它
            name = Path(path).stem
            for ids in GROUPS.values():
                if name in ids:
                    hit = [next(g for g, v in GROUPS.items() if name in v)]
                    break
        if hit is None:
            hit = DEFAULT_GROUPS
        for g in hit:
            if g not in groups:
                groups.append(g)
    skipped = [g for g in groups if g in CHANGED_SKIP]
    if skipped:
        groups = [g for g in groups if g not in CHANGED_SKIP]
        print("[info] 跳过重/慢组：" + ", ".join(skipped) + "（需要时显式 --group " + skipped[0] + "）")
    print("[info] 改动映射到分组：" + ", ".join(groups))
    return groups


def resolve_targets(args) -> list[str]:
    targets: list[str] = []
    if args.all:
        groups = list(GROUPS)
    elif args.group:
        groups = [g.strip() for g in args.group.split(",") if g.strip()]
    elif args.changed:
        groups = changed_groups()
    elif args.tests:
        groups = []          # 只跑点名的套件
    else:
        groups = list(DEFAULT_GROUPS)
    for g in groups:
        if g not in GROUPS:
            sys.exit(f"未知分组 {g}；可用：{', '.join(GROUPS)}")
        for name in GROUPS[g]:
            if name not in targets:
                targets.append(name)
    for name in args.tests:
        if name not in targets:
            targets.append(name)
    for name in list(targets):
        if name in STALE:
            print(f"[stale] {name}：{STALE[name]}")
    return targets


def stop_process_tree(proc: subprocess.Popen) -> None:
    """Stop only this invocation and its children, including the Windows launcher."""
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=5, creationflags=subprocess.CREATE_NO_WINDOW, check=False,
        )
    else:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    if proc.poll() is None:
        proc.kill()
    proc.wait(timeout=5)


def capture_process(cmd: list[str], cwd: Path, timeout: float) -> tuple[int, str, str]:
    """Read diagnostics as they arrive instead of waiting for a broken scene to quit."""
    options = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {"start_new_session": True}
    proc = subprocess.Popen(
        cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1, **options,
    )
    pending: queue.Queue = queue.Queue()
    output: list[str] = []
    stopped = ""
    deadline = time.monotonic() + timeout

    def read_lines() -> None:
        try:
            for line in proc.stdout:
                pending.put(line)
        finally:
            pending.put(None)

    reader = threading.Thread(target=read_lines, daemon=True)
    reader.start()
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                stopped = "TIMEOUT"
                break
            try:
                line = pending.get(timeout=min(.1, remaining))
            except queue.Empty:
                continue
            if line is None:
                break
            output.append(line)
            if FATAL_RE.search(line):
                stopped = "SCRIPT_ERROR"
                break
        if stopped:
            stop_process_tree(proc)
        else:
            try:
                proc.wait(timeout=max(.01, deadline-time.monotonic()))
            except subprocess.TimeoutExpired:
                stopped = "TIMEOUT"
                stop_process_tree(proc)
    finally:
        if proc.poll() is None:
            stop_process_tree(proc)
        reader.join(timeout=1)
        while True:
            try:
                line = pending.get_nowait()
            except queue.Empty:
                break
            if line is not None:
                output.append(line)
        if not reader.is_alive():
            proc.stdout.close()
    return proc.returncode, "".join(output), stopped


def summarize_output(returncode: int, out: str, stopped: str) -> tuple[int, int, str]:
    passed = failed = 0
    reported = False
    for line in reversed(out.splitlines()):
        match = PASS_RE.search(line)
        if match:
            passed, failed = map(int, match.groups())
            reported = True
            break
        match = CHECKS_RE.search(line)
        if match:
            total, failed = map(int, match.groups())
            passed = total - failed
            reported = True
            break
        match = LOWER_RE.search(line)
        if match:
            names = match.group(3) or ""
            failed = len([x for x in names.split(",") if x.strip()]) if names.strip() else int(match.group(4) or 0)
            passed = int(match.group(1)) - failed
            reported = True
            break
    if not reported:
        passed, failed = out.count("✓"), out.count("✗")
        reported = passed + failed > 0
    if stopped == "TIMEOUT":
        return passed, failed, "TIMEOUT"
    fatal = FATAL_RE.search(out)
    if stopped == "SCRIPT_ERROR" or fatal:
        detail = out[fatal.start():].partition("\n")[0] if fatal else "脚本执行中断"
        return passed, failed, "ERROR " + detail
    if not reported:
        return 0, 0, f"ERROR 未输出测试结果（退出码 {returncode}）"
    if returncode == 0 and failed == 0:
        return passed, failed, "PASS"
    errors = [line.strip() for line in out.splitlines() if line.startswith("ERROR:")]
    return passed, failed, "FAIL " + (" | ".join(errors[:3]) or f"退出码 {returncode}")


def run_one(godot: Path, name: str, timeout: float) -> tuple[str, int, int, float, str]:
    scene = f"res://tests/{name}.tscn"
    if not (TESTS / f"{name}.tscn").is_file():
        return name, 0, 0, 0.0, "MISSING"
    started = time.monotonic()
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--max-fps", "240", scene]
    returncode, out, stopped = capture_process(cmd, ROOT, timeout)
    elapsed = time.monotonic() - started
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"{name}.log"
    log_path.write_text(out, encoding="utf-8")
    passed, failed, status = summarize_output(returncode, out, stopped)
    if status != "PASS":
        if status == "TIMEOUT":
            status += f" 超过 {timeout:g}s，已回收本次进程树"
        status += f"；日志：{log_path}"
    return name, passed, failed, elapsed, status


def main() -> int:
    parser = argparse.ArgumentParser(description="分档测试运行器")
    parser.add_argument("tests", nargs="*", help="直接指定套件名（可多个）")
    parser.add_argument("--group", help="分组，逗号分隔：%s" % ", ".join(GROUPS))
    parser.add_argument("--changed", action="store_true", help="按 git 改动自动选组")
    parser.add_argument("--all", action="store_true", help="跑所有分组（含重测试）")
    parser.add_argument("--list", action="store_true", help="列出分组")
    parser.add_argument("--godot", help="Godot 可执行文件路径")
    parser.add_argument("--timeout", type=int, default=180, help="单套件超时秒数（默认 180）")
    parser.add_argument("--heavy-timeout", type=int, default=900, help="重测试超时秒数（默认 900）")
    parser.add_argument("--fail-fast", action="store_true", help="首个失败即停止")
    parser.add_argument("--strict", action="store_true", help="把 KNOWN_RED 也当作失败")
    parser.add_argument("--budget", type=int, default=480, help="整轮时间预算秒数，超了就不再开新套件（默认 480）")
    args = parser.parse_args()

    if args.list:
        for group, ids in GROUPS.items():
            tag = "（重测试，默认不跑）" if group in HEAVY_GROUPS else ""
            print(f"{group:<10}{tag} {len(ids)} 个")
            for name in ids:
                marker = "  " if (TESTS / f"{name}.tscn").is_file() else "✗ "
                print(f"  {marker}{name}")
        if STALE:
            print("\n陈旧测试（默认不跑）：")
            for name, why in STALE.items():
                print(f"  {name} —— {why}")
        return 0

    targets = resolve_targets(args)
    if not targets:
        print("没有要跑的套件")
        return 0
    godot = find_godot(args.godot)
    heavy = set()
    for g in HEAVY_GROUPS:
        heavy.update(GROUPS[g])

    print(f"Godot: {godot}")
    print(f"共 {len(targets)} 个套件：" + ", ".join(targets))
    print("-" * 72)
    failures: list[str] = []
    known_red: list[str] = []
    total_time = 0.0
    started = time.monotonic()
    completed = 0
    skipped: list[str] = []
    for name in targets:
        remaining = args.budget - (time.monotonic() - started)
        if remaining <= 0:
            skipped = targets[targets.index(name):]
            break
        limit = min(args.heavy_timeout if name in heavy else args.timeout, remaining)
        print(f"[run] {name}（最多 {limit:g}s）", flush=True)
        tname, passed, failed, elapsed, status = run_one(godot, name, limit)
        total_time += elapsed
        completed += 1
        kind = status.split(" ")[0]
        # KNOWN_RED 同时覆盖 FAIL 与 ERROR（有些套件断言全过，但退出时泄漏/崩溃报 ERROR）
        label = "KNOWN-RED" if (kind != "PASS" and tname in KNOWN_RED and not args.strict) else kind
        print(f"{tname:<34} {label:<8} {passed:>4}/{passed + failed:<4} {elapsed:>6.1f}s")
        if kind != "PASS":
            detail = status.split(" ", 1)[1] if " " in status else status
            if detail:
                print(f"    └─ {detail[:300]}")
            if label == "KNOWN-RED":
                known_red.append(tname)
            else:
                failures.append(tname)
                if args.fail_fast:
                    break
    print("-" * 72)
    if skipped:
        print(f"[budget] 超时跳过 {len(skipped)} 个：" + ", ".join(skipped[:6]) + ("…" if len(skipped) > 6 else ""))
    print(f"完成 {completed} 个，失败 {len(failures)} 个，已知红灯 {len(known_red)} 个，用时 {total_time:.1f}s")
    print(f"日志：{LOG_DIR}")
    if known_red:
        print("已知红灯（基线如此，--strict 可当失败）：" + ", ".join(known_red))
    if failures:
        print("新增失败：" + ", ".join(failures))
        return 1
    if skipped:
        return 2
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)
    raise SystemExit(main())
