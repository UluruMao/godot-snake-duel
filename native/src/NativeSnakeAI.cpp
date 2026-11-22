/*
Native search and decision ranking used by the playable Godot Snake Duel game.

GDScript supplies occupancy and candidate metrics from its shared simulator.
This C++17 GDExtension executes BFS/flood fill, reconstructs paths and ranks
survival/food/tactical choices. It deliberately does not maintain a second
implementation of snake collisions, growth, mines or combat.

GridKernel owns reusable queue/visited storage. Every GridSearch/worker owns
its own extension instance; no scene nodes, global scratch or locks are used.
Budget accounting, discovery order and ties match the GDScript reference.
The graph and ranking methods return data for the existing AI inspector.
Build with tools/build_native_ai.ps1; native/SConstruct pins the engine API.
*/
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>

namespace snake_native {
using namespace godot;

struct Cell {
    int x, y;
    friend Cell operator+(Cell a, Cell b) { return {a.x + b.x, a.y + b.y}; }
    friend bool operator==(Cell a, Cell b) { return a.x == b.x && a.y == b.y; }
    Vector2i vector() const { return {x, y}; }
};
constexpr std::array<Cell, 4> directions{{{0, -1}, {1, 0}, {0, 1}, {-1, 0}}};

class WorkBudget {
    int64_t remaining_, spent_ = 0;
    bool exhausted_ = false;
public:
    explicit WorkBudget(int64_t remaining) : remaining_(std::max<int64_t>(0, remaining)) {}
    bool spend() {
        if (spent_ >= remaining_) { exhausted_ = true; return false; }
        ++spent_;
        return true;
    }
    void report(Dictionary &result) const {
        result["spent"] = spent_;
        result["exhausted"] = exhausted_;
    }
};

class GridKernel {
    int width_ = 0, height_ = 0;
    uint32_t generation_ = 0;
    std::vector<int> queue_;
    std::vector<uint32_t> seen_;
    std::vector<uint8_t> blocked_;
    bool contains(Cell c) const { return c.x >= 0 && c.y >= 0 && c.x < width_ && c.y < height_; }
    int index(Cell c) const { return c.y * width_ + c.x; }
    Cell cell(int i) const { return {i % width_, i / width_}; }
    bool prepare(int64_t width, int64_t height, Vector2i start, const Dictionary &blocked) {
        // Reject malformed extension calls before indexing or allocating storage.
        if (width < 1 || height < 1 || width > 4096 || height > 4096 || width * height > 1048576)
            return false;
        width_ = static_cast<int>(width);
        height_ = static_cast<int>(height);
        if (!contains({start.x, start.y})) return false;
        const auto size = static_cast<std::size_t>(width_ * height_);
        queue_.resize(size);
        seen_.resize(size, 0);
        blocked_.assign(size, 0);
        if (++generation_ == 0) {
            std::fill(seen_.begin(), seen_.end(), 0);
            ++generation_;
        }
        const Array keys = blocked.keys();
        for (int64_t i = 0; i < keys.size(); ++i) {
            if (keys[i].get_type() != Variant::VECTOR2I) return false;
            const Vector2i value = keys[i];
            const Cell c{value.x, value.y};
            if (contains(c)) blocked_[index(c)] = 1;
        }
        return true;
    }
public:
    Dictionary scan(int64_t width, int64_t height, Vector2i start,
                    const Dictionary &blocked, Vector2i goal, int64_t remaining) {
        if (!prepare(width, height, start, blocked)) {
            Dictionary error;
            error["error"] = "Invalid grid search input";
            return error;
        }
        const int size = width_ * height_, origin = index({start.x, start.y});
        PackedInt32Array parents, distances;
        parents.resize(size);
        parents.fill(0); // Match the reference's undiscovered predecessor values.
        distances.resize(size);
        distances.fill(-1);
        parents.set(origin, origin);
        distances.set(origin, 0);
        queue_[0] = origin;
        seen_[origin] = generation_;
        int tail = 1, cursor = 0;
        WorkBudget budget(remaining);
        bool complete = true;
        while (cursor < tail) {
            // A failed attempt, rather than merely reaching the cap, truncates.
            if (!budget.spend()) { complete = false; break; }
            const int current = queue_[cursor++];
            const Cell from = cell(current);
            if (from == Cell{goal.x, goal.y}) break;
            for (const Cell d : directions) {
                const Cell next = from + d;
                if (!contains(next)) continue;
                const int to = index(next);
                if (blocked_[to] || seen_[to] == generation_) continue;
                seen_[to] = generation_;
                parents.set(to, current);
                distances.set(to, distances[current] + 1);
                queue_[tail++] = to;
            }
        }
        TypedArray<Vector2i> reached;
        reached.resize(tail);
        for (int i = 0; i < tail; ++i) reached[i] = cell(queue_[i]).vector();
        Dictionary result;
        result["cells"] = reached;
        result["parents"] = parents;
        result["distances"] = distances;
        result["width"] = width_;
        result["height"] = height_;
        result["complete"] = complete;
        budget.report(result);
        return result;
    }
    Dictionary area(int64_t width, int64_t height, Vector2i start,
                    const Dictionary &blocked, int64_t required, int64_t remaining) {
        if (!prepare(width, height, start, blocked)) {
            Dictionary error;
            error["error"] = "Invalid flood fill input";
            return error;
        }
        const int origin = index({start.x, start.y});
        queue_[0] = origin;
        seen_[origin] = generation_;
        int tail = 1, cursor = 0;
        WorkBudget budget(remaining);
        // Finish the current cell's neighbors before testing the area threshold.
        // This preserves the reference's frontier and exact logical work count.
        while (cursor < tail && tail < required) {
            if (!budget.spend()) break;
            const Cell from = cell(queue_[cursor++]);
            for (const Cell d : directions) {
                const Cell next = from + d;
                if (!contains(next)) continue;
                const int to = index(next);
                if (blocked_[to] || seen_[to] == generation_) continue;
                seen_[to] = generation_;
                queue_[tail++] = to;
            }
        }
        Dictionary result;
        result["valid"] = tail >= required;
        result["area"] = tail;
        budget.report(result);
        return result;
    }
    TypedArray<Vector2i> area_cells(int64_t width, int64_t count) const {
        TypedArray<Vector2i> result;
        if (width <= 0 || count < 0 || count > static_cast<int64_t>(queue_.size())) return result;
        result.resize(count);
        for (int64_t i = 0; i < count; ++i) result[i] = Vector2i(static_cast<int>(queue_[i] % width), static_cast<int>(queue_[i] / width));
        return result;
    }
};

// Candidate data comes from the live simulator, never from a second native world.
struct Candidate {
    bool legal, evaluated, food;
    int tier, area, exits, viable, distance;
    double utility, threat, clearance;
    explicit Candidate(const Dictionary &d) :
        legal(d.get("legal", false)), evaluated(d.get("evaluated", true)),
        food(d.get("food_valid", false)), tier(d.get("tier", 0)), area(d.get("area", 0)),
        exits(d.get("continuations", 0)), viable(d.get("viable_continuations", 0)),
        distance(d.get("distance", 1000000)), utility(d.get("utility", 0.0)),
        threat(d.get("threat", 1.0)), clearance(d.get("clearance", 0.0)) {}
};
enum class Planner { Bfs, Safety, Purple, Red, Golden };

class Ranking {
public:
    static bool better(const Candidate &a, const Candidate &b, bool food, Planner planner) {
        if (food) {
            if (planner == Planner::Purple && !Math::is_equal_approx(a.utility, b.utility))
                return a.utility > b.utility;
            if (a.distance != b.distance) return a.distance < b.distance;
        } else {
            if (planner >= Planner::Purple && a.viable != b.viable) return a.viable > b.viable;
            if (a.exits != b.exits) return a.exits > b.exits;
            if (!Math::is_equal_approx(a.threat, b.threat)) return a.threat < b.threat;
        }
        return a.area > b.area; // Equality retains straight/left/right insertion order.
    }
    static int choose(const Array &input, Planner planner, bool runtime, bool star) {
        std::vector<Candidate> candidates;
        candidates.reserve(static_cast<std::size_t>(input.size()));
        int best_tier = 0;
        for (int64_t i = 0; i < input.size(); ++i) {
            candidates.emplace_back(static_cast<Dictionary>(input[i]));
            const auto &c = candidates.back();
            if (c.legal && (!runtime || c.evaluated)) best_tier = std::max(best_tier, c.tier);
        }
        bool food_options = false;
        if (!runtime) for (const auto &c : candidates)
            food_options |= c.legal && c.tier == best_tier && c.food;
        int best = -1;
        for (int i = 0; i < static_cast<int>(candidates.size()); ++i) {
            const auto &a = candidates[i];
            if (!a.legal || a.tier != best_tier || (runtime && !a.evaluated) || (food_options && !a.food)) continue;
            bool preferred = best < 0;
            if (best >= 0) {
                const auto &b = candidates[best];
                const bool evade = runtime && (planner == Planner::Golden || (star && planner == Planner::Red));
                if (evade && a.exits == b.exits && Math::is_equal_approx(a.threat, b.threat) &&
                    !Math::is_equal_approx(a.clearance, b.clearance)) preferred = a.clearance > b.clearance;
                else preferred = better(a, b, food_options, planner);
            }
            if (preferred) best = i;
        }
        return best;
    }
};

class NativeSnakeAI : public RefCounted {
    GDCLASS(NativeSnakeAI, RefCounted)
    GridKernel grid_;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("scan", "width", "height", "start", "blocked", "goal", "remaining"), &NativeSnakeAI::scan);
        ClassDB::bind_method(D_METHOD("area_at_least", "width", "height", "start", "blocked", "required", "remaining"), &NativeSnakeAI::area_at_least);
        ClassDB::bind_method(D_METHOD("area_cells", "width", "count"), &NativeSnakeAI::area_cells);
        ClassDB::bind_method(D_METHOD("path", "scan", "goal"), &NativeSnakeAI::path);
        ClassDB::bind_method(D_METHOD("choose_collector", "candidates", "planner"), &NativeSnakeAI::choose_collector);
        ClassDB::bind_method(D_METHOD("choose_runtime", "candidates", "planner", "star"), &NativeSnakeAI::choose_runtime);
        ClassDB::bind_method(D_METHOD("better", "a", "b", "food", "planner"), &NativeSnakeAI::better);
        ClassDB::bind_method(D_METHOD("food_utility", "candidate", "weights", "advanced"), &NativeSnakeAI::food_utility);
        ClassDB::bind_method(D_METHOD("evade_utility", "candidate", "required", "clearance", "weights", "star"), &NativeSnakeAI::evade_utility);
        ClassDB::bind_method(D_METHOD("attack_utility", "candidate", "required", "interception", "restriction", "weights"), &NativeSnakeAI::attack_utility);
    }
public:
    Dictionary scan(int64_t w, int64_t h, Vector2i start, const Dictionary &blocked, Vector2i goal, int64_t remaining) {
        return grid_.scan(w, h, start, blocked, goal, remaining);
    }
    Dictionary area_at_least(int64_t w, int64_t h, Vector2i start, const Dictionary &blocked, int64_t required, int64_t remaining) {
        return grid_.area(w, h, start, blocked, required, remaining);
    }
    TypedArray<Vector2i> area_cells(int64_t width, int64_t count) const { return grid_.area_cells(width, count); }
    TypedArray<Vector2i> path(const Dictionary &scan, Vector2i goal) const {
        TypedArray<Vector2i> result;
        const int width = scan.get("width", 0), height = scan.get("height", 0);
        const PackedInt32Array distances = scan.get("distances", PackedInt32Array());
        const PackedInt32Array parents = scan.get("parents", PackedInt32Array());
        if (width <= 0 || goal.x < 0 || goal.y < 0 || goal.x >= width || goal.y >= height ||
            parents.size() != int64_t(width) * height || distances.size() != parents.size()) return result;
        int current = goal.y * width + goal.x;
        if (distances[current] < 0) return result;
        std::vector<Vector2i> reversed;
        for (int64_t n = 0; n < parents.size(); ++n) {
            reversed.emplace_back(current % width, current / width);
            if (parents[current] == current) {
                for (auto it = reversed.rbegin(); it != reversed.rend(); ++it) result.push_back(*it);
                return result;
            }
            current = parents[current];
            if (current < 0 || current >= parents.size()) return {};
        }
        return {}; // Malformed parent cycle must never hang the game.
    }
    int64_t choose_collector(const Array &candidates, int64_t planner) const {
        return Ranking::choose(candidates, static_cast<Planner>(planner), false, false);
    }
    int64_t choose_runtime(const Array &candidates, int64_t planner, bool star) const {
        return Ranking::choose(candidates, static_cast<Planner>(planner), true, star);
    }
    bool better(const Dictionary &a, const Dictionary &b, bool food, int64_t planner) const {
        return Ranking::better(Candidate(a), Candidate(b), food, static_cast<Planner>(planner));
    }
    double food_utility(const Dictionary &c, const PackedFloat64Array &weights, bool advanced) const {
        if (weights.size() != 4) return 0;
        const double required = c.get("required", 0.0);
        if (required <= 0) return 0;
        const bool valid = c.get("food_valid", false);
        const double food = valid ? std::min(1.0, double(c.get("reward_multiplier", 1.0)) / (1.0 + double(c.get("distance", 1000000)))) : 0;
        const double space = std::clamp(double(c.get("area", 0)) / (2.0 * static_cast<double>(required)), 0.0, 1.0);
        const double exits = double(c.get(advanced ? "viable_continuations" : "continuations", 0)) / 3.0;
        return weights[0] * food + weights[1] * space + weights[2] * exits - weights[3] * double(c.get("threat", 1.0));
    }
    double evade_utility(const Dictionary &c, int64_t required, double clearance, const PackedFloat64Array &w, bool star) const {
        if (w.size() != 9 || required <= 0) return 0;
        const double mobility = double(c.get("viable_continuations", 0)) / 3.0;
        const double space = std::clamp(double(c.get("area", 0)) / (2.0 * static_cast<double>(required)), 0.0, 1.0);
        const double clearance_weight = std::max(w[4], star ? w[5] : w[6]);
        return std::max(w[0], w[1]) * mobility + std::max(w[2], w[3]) * space +
            clearance_weight * clearance - std::max(w[7], w[8]) * double(c.get("threat", 1.0));
    }
    double attack_utility(const Dictionary &c, int64_t required, double interception, double restriction, const PackedFloat64Array &w) const {
        if (w.size() != 5 || required <= 0) return 0;
        const double mobility = double(c.get("viable_continuations", 0)) / 3.0;
        const double space = std::clamp(double(c.get("area", 0)) / (2.0 * required), 0.0, 1.0);
        return w[0] * interception + w[1] * restriction + w[2] * mobility + w[3] * space - w[4] * double(c.get("threat", 1.0));
    }
};

void initialize(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<NativeSnakeAI>();
}
void terminate(ModuleInitializationLevel) {}
} // namespace snake_native

extern "C" GDExtensionBool GDE_EXPORT snake_ai_library_init(
    GDExtensionInterfaceGetProcAddress get_proc_address,
    GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(snake_native::initialize);
    init.register_terminator(snake_native::terminate);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
