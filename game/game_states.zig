const std = @import("std");
const delve = @import("delve");
const entities = @import("entities.zig");
const game = @import("game.zig");

pub const GameState = struct {
    impl_ptr: *anyopaque, // Pointer to the actual GameState struct
    typename: []const u8,

    // game state interface methods
    _interface_tick: *const fn (impl: *anyopaque, delta: f32) void,
    _interface_on_start: *const fn (impl: *anyopaque, game_instance: *game.GameInstance) anyerror!void,
    _interface_deinit: *const fn (impl: *anyopaque) void,

    pub fn onStart(self: *GameState, game_instance: *game.GameInstance) !void {
        try self._interface_on_start(self.impl_ptr, game_instance);
    }

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
    owner: *game.GameInstance,

    pub fn setState(self: *GameStateStack, new_state: GameState) void {
        // deinit old state for now while we just have one
        if (self.current) |*state| {
            state.deinit();
        }

        self.current = new_state;
        self.current.?.onStart(self.owner) catch {
            delve.debug.fatal("Could not start new game state {s}!", .{new_state.typename});
        };
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

    pub fn getStates(self: *GameStateStack) []*GameState {
        if (self.current == null)
            return [_]*GameState{};

        return [_]*GameState{self.current};
    }
};
