from pathlib import Path
from lupa import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
package_path = str(root / "?.lua").replace("\\", "/") + ";" + str(root / "?/init.lua").replace("\\", "/")
lua.execute(f'package.path = "{package_path};" .. package.path')
for name in (
    "navigation_test.lua", "situation_test.lua", "estimator_test.lua",
    "ore_scanner_test.lua",
):
    test = (root / "tests" / name).read_text(encoding="utf-8")
    result = lua.execute(test)
    if result is not True:
        raise SystemExit(f"{name} did not return true")
    print(f"{name}: OK")
