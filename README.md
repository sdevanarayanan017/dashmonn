# 🥷 Dashmon

A fast-paced, 3D endless runner built in **Godot 4** featuring fluid traversal mechanics, grappling hook flight, dynamic obstacle generation, and an ominous chaser demon.

---

## 🎮 Overview

In **Dashmon**, you play as a stealthy shadow ninja sprinting through an ever-changing obstacle course. Dodge hazards, slide under barriers, grapple across distances, collect booster tokens, and outrun the demon monster that hunts you in the shadows.

---

## ✨ Features

- **🥷 Shadow Ninja Hero**:
  - Procedural humanoid character with black shinobi suit, pitch-black mask, piercing white eyes, and dark crimson headband.
  - Custom procedural running, jumping, slide crouching, and superhero landing animations.
  - Dynamic smoke particle trails.

- **⚡ Fluid Traversal Mechanics**:
  - **Lane Steering & Smooth Acceleration**: Speed gradually scales from base velocity up to high-speed sprints.
  - **Jump & Double-Jump**: Clear elevated obstacles and gaps.
  - **Slide**: Duck under low barriers and falling logs.
  - **Booster Dash**: Collect 3 booster tokens along the track to trigger high-speed invulnerable dash.
  - **Grappling Hook & Meteor Flight**: Launch a grappling cable, ascend into soaring meteor flight, and plunge back with a ground-shaking divekick.

- **👹 Dynamic Demon Chaser**:
  - The monster stalks from the shadows, emerging periodically after reaching milestone distances.
  - Proximity warning cues when the chaser enters hunting mode.

- **🌲 Intelligent Track & Obstacle Generation**:
  - Non-interfering obstacle placement (falling trees, road blocks, spikes) with calibrated spacing.
  - Track coin clusters and special booster tokens.

- **📊 Highscore & Menus**:
  - Start Run and Game Over menus.
  - Persistent highscore tracking saved locally (`user://highscore.dat`).
  - Real-time HUD showing current score, best score, distance traveled, and collected tokens.

---

## 🕹️ Controls

| Action | Keyboard | Controller / Gamepad |
| :--- | :--- | :--- |
| **Move Left / Right** | `A` / `D` or `Left Arrow` / `Right Arrow` | Left Analog Stick |
| **Jump / Double-Jump** | `Space` / `W` / `Up Arrow` | `A` Button |
| **Slide** | `S` / `Down Arrow` | `B` Button |
| **Dash (when charged)** | `Space` / `Enter` | `X` Button |
| **Grappling Hook & Divekick** | `F` / `Q` | `Y` Button / `RB` (Right Shoulder) |
| **Restart Game** | `R` (on Game Over) | — |

---

## 🚀 Getting Started

### Prerequisites

- [Godot Engine 4.x](https://godotengine.org/download) (Godot 4.3 or newer recommended, with Jolt 3D Physics support).

### Installation & Running

1. **Clone the repository:**
   ```bash
   git clone https://github.com/sdevanarayanan017/dashmonn.git
   cd dashmonn
   ```

2. **Open in Godot:**
   - Launch Godot Engine.
   - Click **Import** and browse to the cloned `dashmonn` directory.
   - Select `project.godot` and click **Import & Edit**.

3. **Play:**
   - Press **F5** (or click the **Play** button in the top-right corner) to run the main scene (`res://main.tscn`).

---

## 📁 Project Structure

```
dashmon/
├── main.tscn / main.gd        # Game loop, track spawner, HUD, highscore system
├── player.tscn / player.gd    # Ninja hero, movement physics, abilities, animations
├── enemy.tscn / enemy.gd      # Demon chaser AI, hunting phases, proximity cues
├── falling_tree.gd            # Physics-based dynamic obstacle
├── track_item.tscn / .gd      # Coins and booster collectible tokens
├── project.godot              # Godot project configuration & rendering settings
└── assets/                    # Textures, models, materials, and UI elements
```

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
