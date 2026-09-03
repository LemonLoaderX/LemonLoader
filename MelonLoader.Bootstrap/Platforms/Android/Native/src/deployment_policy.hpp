#pragma once

#include <string>

namespace lemon::bootstrap::deployment {

enum class Policy {
    seed,
    upgrade,
    refresh,
    enforce,
};

enum class Action {
    preserve,
    install,
    replace,
    remove,
};

constexpr Action decide_current(
    Policy policy,
    bool revision_changed,
    bool exists,
    bool matches_packaged,
    bool has_previous_state,
    bool matches_previous_packaged) {
    if (!exists) {
        return Action::install;
    }
    if (matches_packaged) {
        return Action::preserve;
    }
    switch (policy) {
        case Policy::seed:
            return Action::preserve;
        case Policy::upgrade:
            return has_previous_state && matches_previous_packaged
                ? Action::replace
                : Action::preserve;
        case Policy::refresh:
            return revision_changed ? Action::replace : Action::preserve;
        case Policy::enforce:
            return Action::replace;
    }
    return Action::preserve;
}

constexpr Action decide_obsolete(
    Policy previous_policy,
    bool revision_changed,
    bool exists,
    bool matches_previous_packaged) {
    if (!exists) {
        return Action::preserve;
    }
    switch (previous_policy) {
        case Policy::seed:
            return Action::preserve;
        case Policy::upgrade:
            return matches_previous_packaged ? Action::remove : Action::preserve;
        case Policy::refresh:
        case Policy::enforce:
            return revision_changed ? Action::remove : Action::preserve;
    }
    return Action::preserve;
}

constexpr bool requires_continuous_content_check(Policy policy) {
    return policy == Policy::enforce;
}

inline const char* name(Policy policy) {
    switch (policy) {
        case Policy::seed:
            return "seed";
        case Policy::upgrade:
            return "upgrade";
        case Policy::refresh:
            return "refresh";
        case Policy::enforce:
            return "enforce";
    }
    return "";
}

inline bool parse(const std::string& value, Policy& policy) {
    if (value == "seed") {
        policy = Policy::seed;
    } else if (value == "upgrade") {
        policy = Policy::upgrade;
    } else if (value == "refresh") {
        policy = Policy::refresh;
    } else if (value == "enforce") {
        policy = Policy::enforce;
    } else {
        return false;
    }
    return true;
}

static_assert(decide_current(Policy::seed, true, true, false, true, true) ==
              Action::preserve);
static_assert(decide_current(Policy::upgrade, true, true, false, true, true) ==
              Action::replace);
static_assert(decide_current(Policy::upgrade, true, true, false, true, false) ==
              Action::preserve);
static_assert(decide_current(Policy::refresh, true, true, false, false, false) ==
              Action::replace);
static_assert(decide_current(Policy::refresh, false, true, false, true, false) ==
              Action::preserve);
static_assert(decide_current(Policy::enforce, false, true, false, false, false) ==
              Action::replace);
static_assert(decide_obsolete(Policy::seed, true, true, true) == Action::preserve);
static_assert(decide_obsolete(Policy::upgrade, true, true, true) == Action::remove);
static_assert(decide_obsolete(Policy::upgrade, true, true, false) == Action::preserve);
static_assert(decide_obsolete(Policy::refresh, true, true, false) == Action::remove);
static_assert(!requires_continuous_content_check(Policy::seed));
static_assert(!requires_continuous_content_check(Policy::upgrade));
static_assert(!requires_continuous_content_check(Policy::refresh));
static_assert(requires_continuous_content_check(Policy::enforce));

}  // namespace lemon::bootstrap::deployment
