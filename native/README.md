# Native AI integration

The playable game calls `src/NativeSnakeAI.cpp` through Godot GDExtension. This authored C++17 source is **333 total lines**, including comments and delimiters, and is the recommended live-game admissions sample.

## Responsibility boundary

| Native C++ | GDScript integration |
|---|---|
| BFS, flood fill, distance and predecessor maps | Authoritative movement, growth, collisions and combat |
| Shortest-path reconstruction | Mine/item timing, tail-route replay and opponent forecasts |
| Food, evasion and attack utility calculations | Candidate metrics from the shared simulator |
| Safety-tier filtering, candidate ranking and deterministic ties | Profiles, worker scheduling and fresh first-step checks |
| Per-instance queue and visited storage | CRT presentation and the existing AI inspector |

`GridKernel`, `WorkBudget`, `Candidate` and `Ranking` separate graph storage, computation limits and policy. The engine-facing `NativeSnakeAI` inherits `RefCounted`; `GDCLASS` and `D_METHOD` register its methods. Cell operators express grid movement. Whole searches cross the language boundary, rather than individual neighbor expansions.

Each `GridSearch`/worker owns its native scratch instance. Native methods do not access scene nodes or implement a second collision simulator. Native work is charged to the same 8,192-operation allowance, including current-safety reservations. Discovery order, partial frontiers, threshold overshoot, approximate comparisons and ties match the GDScript reference.

## Run and compare

The included libraries target **Godot 4.7, Windows x86_64**, with single-precision engine vectors. Open the project in Godot 4.7.2 and run normally. Developer mode → **More diagnostics** shows `Backend: C++ GDExtension`.

Start the current GDScript reference backend with:

```powershell
& '<Godot executable>' --path . -- --gdscript-ai
```

The backend is selected at startup, without changing a global policy while workers run. When the native class is unavailable, the adapter uses the reference; an unsupported/missing library can still generate an engine load error. Install a matching build, or omit the extension descriptor from a reference-only distribution. Only Windows binaries are supplied and verified.

## Rebuild

Install Visual Studio's x64 C++ tools and Python 3.8 or later. Close Snake Duel editor/game instances before replacing a loaded DLL, then run from the project root:

```powershell
./tools/build_native_ai.ps1 -Godot '<Godot 4.7.2 console executable>' -Python '<Python executable>' -VsDevCmd '<Visual Studio Common7/Tools/VsDevCmd.bat>'
```

The default builds both configurations with four jobs. `-Target Debug` or `-Target Release` selects one. `VsDevCmd` may be omitted when `vswhere` locates the C++ installation.

The script pins official godot-cpp commit `7fd5c4bc3efda6487fd6e6486c50016faa622f92`, installs task-local SCons 4.10.1 and dumps the specified engine's extension API. Downloads, bindings, objects and compiler caches stay under `.godot/native_ai`. The trimmed bindings include RefCounted and OS (used by binding diagnostics). The authored source uses MSVC `/W4 /WX /fp:precise`; upstream translation units retain their warning policy.

Keep the extension descriptor, its UID and both `bin/*.dll` libraries in Windows copies. Intermediate `.lib`, `.exp`, `.obj`, `.pdb`, SCons state and editor DLL copies are ignored. The binding's MIT notice is included in `LICENSE.godot-cpp.txt`.

## Verification

The integration passed **221 unit tests** with each gameplay backend, all **six playable-scene smokes**, and the native differential suite through the **release DLL loaded in Godot**. All **291 pre-integration detailed decisions match exactly**, including routes, reachable cells, candidate metrics, logical work and exhaustion flags.

Fixtures cover search order, parent links, truncated results, area thresholds, approximate numeric ties, safety/food/evasion priorities, utility formulas, invalid input, parent cycles and eight concurrent independent native workers. Editor import and actual CRT rendering were verified. Standalone executable exports remain untested because Godot 4.7.2 export templates are not installed; loading both DLL configurations is verified.

The unit fixtures, scene smoke runners and profiling tools are maintained in the development project; this upload folder contains the playable runtime, native source and reproducible build setup. The measurements below were taken from the development project.

## Measured performance

Sequential local CPU probes used Godot 4.7.2 on Windows, optimized MSVC native libraries, seed 42, three warmups and either 250 graph queries or 20 complete synchronous decisions. Timings include the bridge and compare against the current GDScript backend.

| CPU workload | Reference mean | Native mean |
|---|---:|---:|
| 30 × 25 BFS plus path reconstruction | 1.950 ms | 0.047 ms |
| Purple on a clear fixed snapshot | 19.163 ms | 12.913 ms |
| Red on a clear fixed snapshot | 8.788 ms | 4.816 ms |
| Golden on a clear fixed snapshot | 14.160 ms | 8.317 ms |
| Purple with eight mines and sixteen diamonds | 30.024 ms | 27.345 ms |
| Purple with long bodies, hazards and 192 obstacles | 26.367 ms | 26.088 ms |

All non-timing benchmark outputs and logical work counts match. The isolated graph query improved substantially; full AI work improved less because simulator/hazard work remains in GDScript.

Rendered probes retained the same CRT, 1152 × 648 window, 30 warmup frames and 600 measured frames per case. One-Purple clear strategy-worker mean fell from 13.52 to 6.73 ms, but its worst world-update gap rose from 34.68 to 36.11 ms. One-Purple heavy strategy mean rose from 43.18 to 45.23 ms, with its worst gap rising from 56.60 to 61.65 ms. All cases remained around 50 simulation ticks/s. These measurements support a faster graph kernel, not a universal FPS, latency or survival improvement.

The boundary follows the official [godot-cpp documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/about_godot_cpp.html) and [thread-safety guidance](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
