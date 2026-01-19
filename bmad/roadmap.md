# Roadmap - King of the Apero

## ✅ Phase 1: Mechanical Prototype (POC) - COMPLETED
Focus: Core gameplay loop, multiplayer synchronization, and basic rules.

- [x] **Arena & Grid:**
    - 5x5 / 6x6 Grid generation.
    - Movement validation (Orthogonal/Diagonal).
    - Cell highlighting.
- [x] **Wrestlers (Pawns):**
    - Spawn logic (Host vs Client).
    - Stats (HP).
    - Basic Actions (Move, Attack).
- [x] **Card System:**
    - Deck management (Draw, Shuffle, Discard).
    - Hand management (Limit, Draw per turn).
    - Card types (Move, Attack, Joker).
    - Network Sync (Hidden hands, synchronized plays).
- [x] **Game Loop:**
    - Turn-based system (Active player check).
    - Action points / Card usage limit.
    - End turn logic.
- [x] **Multiplayer Architecture:**
    - WebSocket Server/Client.
    - Lobby (Host/Join).
    - State Synchronization (RPCs).
    - Reconnection/Rematch handling.
- [x] **Victory Conditions:**
    - HP reaches 0.
    - Opponent disconnects.
    - Game Over UI & Restart.

## 🚧 Phase 2: Visual Polish & Game Feel (CURRENT)
Focus: Making the game look and feel good.

- [ ] **3D Assets:** Replace placeholders (Capsules/Cubes) with actual 3D models (Wrestlers, Ring).
- [ ] **Animations:** Idle, Walk, Punch, Get Hit, KO, Victory.
- [ ] **VFX:** Hit particles, Selection markers, Card trails.
- [ ] **Audio:** SFX (Impacts, Cards, UI), Background Music.
- [ ] **Camera:** Dynamic camera movements, screenshake on impact.

## 📅 Phase 3: Content & Expansion
Focus: Replayability and depth.

- [ ] **More Cards:** Special moves, defensive cards.
- [ ] **Character Selection:** Different wrestlers with unique stats/passives.
- [ ] **Mobile UI:** Touch controls optimization.
- [ ] **Web Build:** PWA optimization.

## 🚀 Phase 4: Online Services & Production
Focus: Infrastructure for public release (Nakama Backend).

- [x] **Nakama Setup:** Deploy Nakama + DB via Docker Compose (Local).
- [x] **Godot Plugin:** Install official Nakama Client SDK.
- [ ] **Authentication:** Implement Device ID / Email auth.
- [ ] **Unified Multiplayer:** Implement Host/Join & Matchmaking via Manual Socket (JSON).
- [ ] **Network Protocol:** Replace RPCs with custom JSON message handling ("Lightweight Bridge").