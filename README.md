# Super Boarding Party

<img width="1072" alt="Screen Shot 2024-11-08 at 9 48 47 AM" src="https://github.com/user-attachments/assets/25e7e292-b592-4e49-b803-8bf140b31480">

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

## Copyright Info

[Diabolus Ex](https://www.doomworld.com/forum/topic/101473-gzdoom-diabolus-ex-v11/) textures are by Arvell, and are used with their permission.

## Delve Framework improvements needed

- Color is off during lerping, maybe due to packed colors? Just use float colors instead
- Quake map UVs are off when translating the maps
- Quake maps need be able to make meshes per-quakemap entity
- Need a shader that works for lighting and sprites
