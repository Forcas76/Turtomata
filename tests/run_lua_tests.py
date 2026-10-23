from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
package_path = str(root / "?.lua").replace("\\", "/") + ";" + str(root / "?/init.lua").replace("\\", "/")
lua.execute(f'package.path = "{package_path};" .. package.path')
for name in (
    "navigation_test.lua", "situation_test.lua", "estimator_test.lua",
    "ore_scanner_test.lua",
    "ore_discovery_test.lua",
    "localization_test.lua",
    "base_dock_test.lua",
    "base_dock_modded_test.lua",
    "registry_test.lua",
    "job_setup_test.lua",
    "remote_test.lua",
    "ui_secret_test.lua",
    "downloader_update_test.lua",
):
    if name == "downloader_update_test.lua":
        lua.globals().DOWNLOADER_SOURCE = (root / "downloader.lua").read_text(encoding="utf-8")
    test = (root / "tests" / name).read_text(encoding="utf-8")
    result = lua.execute(test)
    if result is not True:
        raise SystemExit(f"{name} did not return true")
    print(f"{name}: OK")

parse_lua = lua.eval("function(source, name) return assert(load(source, name)) end")
for source_path in root.glob("*.lua"):
    parse_lua(source_path.read_text(encoding="utf-8"), source_path.name)
print("Lua syntax: OK")
