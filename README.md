# Gazebo steer_bot track generator

Utilities to build a **slalom test track** for the [`steer_bot`](https://github.com/CIR-KIT/steer_drive_ros) Ackermann/steering robot in Gazebo: a sinusoidal road lined with yellow (left) and blue (right) traffic cones — the layout used in autonomous-racing style tests — plus randomly placed trees.

## Contents

```
models/      Gazebo models: cone (meshes), cone_yellow, cone_blue, grass, mat (ground plane with texture)
templates/   SDF templates spawned at runtime: road segment, tree
scripts/
  install_models.sh   copies models/ into ~/.gazebo/models
  generate_track.py   spawns road, cones and trees through the Gazebo ROS service
```

## Requirements

- Ubuntu with ROS (Noetic) and Gazebo, the `steer_bot` simulation running in the `steer_bot` namespace
- Python 3 with `numpy`, `scipy` and `rospy`
- Standard Gazebo models `asphalt_plane` and `oak_tree` (downloaded automatically by Gazebo)

## Usage

```bash
./scripts/install_models.sh          # once; set GAZEBO_MODEL_DIR to change the destination
# start the steer_bot simulation, then:
python3 scripts/generate_track.py --seed 1
```

The track is generated from `y = sin(x/5)·x/2` for `x ∈ [0, 50)`; cones sit 2 m from the centre line on either side (a few are skipped on the tightest bends, see `SKIP_*_POINTS`), and 40 trees are placed at least 3 m away from the cones. Change the constants at the top of `generate_track.py` to alter the geometry; `--seed` makes tree placement reproducible.
