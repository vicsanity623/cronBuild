# CRONBUILD DIRECTIVES — Web Game Project

## Project Overview
You are building a browser-based 2D game using vanilla HTML, CSS, and JavaScript. Zero external dependencies. The game features a canvas-based rendering loop, player movement, enemy AI, collision detection, scoring, and progressive difficulty.

## Development Standards
- Use vanilla JS classes and modular functions
- Canvas-based rendering (no frameworks)
- RequestAnimationFrame game loop
- Zero external dependencies (no libraries, no CDN)
- All code in .js files, CSS in .css files, HTML in index.html
- Mobile-responsive with touch controls where possible
- Sound effects via Web Audio API (no audio files)

## Technical Rules
- Game runs at 60fps via requestAnimationFrame
- Delta-time based movement (frame-rate independent)
- Object pooling for performance
- Collision detection via AABB or circle-based
- Local storage for high scores and settings
- PWA-ready with manifest.json and service worker

## Memory Protocol
- Append EXACTLY one line to MEMORY.md after each successful merge
- Format: [DAY X] | YYYY-MM-DD | Feature description | NEXT: next feature
- Targets must be incremental and achievable in one session
