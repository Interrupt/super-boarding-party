# Super Boarding Party

An example game built using the Delve Framework, based on a 7dayfps project of mine.

Currently targets Zig 0.13.0

Compile for desktop:
```
➜  zig build run
```

Compile for web with:
```
➜  zig build run -Dtarget=wasm32-emscripten
```

## TODO

- Quake Levels
  - Streaming: map entities should load their maps when you get close to them
  - Movers: elevators and doors from Quake map entities
- Entity System
  - Physics / logic should tick on the FixedTick instead of Tick
- Game
  - Doors / Elevators
  - Health pickups
  - Basic level to run through

## Delve Framework improvements needed

- Color is off during lerping, maybe due to packed colors? Just use float colors instead
- Quake map UVs are off when translating the maps
- Quake maps need be able to make meshes per-quakemap entity
- Need a shader that works for lighting and sprites
