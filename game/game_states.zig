const std = @import("std");
const delve = @import("delve");

pub const GameState = struct {
    impl_ptr: *anyopaque, // Pointer to the actual GameState struct
    typename: []const u8,

    // game state interface methods
    _interface_tick: *const fn (self: *anyopaque, delta: f32) void,
    _interface_deinit: *const fn (self: *anyopaque) void,

    // _interface_draw: *const fn (self: *anyopaque) void,
    // _nterface_physics_tick: *const fn (self: *anyopaque, delta: f32) void,
    // _interface_deinit: *const fn (self: *anyopaque) void,

    pub fn tick(self: *GameState, delta: f32) void {
        self._interface_tick(self.impl_ptr, delta);
    }

    pub fn deinit(self: *GameState) void {
        self._interface_deinit(self.impl_ptr);
    }
};

/// A stack of game states, so that a pause screen could overlay a game for example
pub const GameStateStack = struct {
    current: ?GameState = null,

    pub fn setState(self: *GameStateStack, new_state: GameState) void {
        // deinit old state for now while we just have one
        if (self.current) |*state| {
            state.deinit();
        }

        self.current = new_state;
    }

    pub fn tick(self: *GameStateStack, delta: f32) void {
        if (self.current) |*state| {
            state.tick(delta);
        }
    }

    pub fn deinit(self: *GameStateStack) void {
        if (self.current) |*state| {
            state.deinit();
        }
    }
};
