# Gazebo steer_bot track generator

Utilities that build a **slalom test track** for the `steer_bot` steering robot in Gazebo: a sinusoidal road lined with yellow (left) and blue (right) traffic cones, as in autonomous-racing style tests, plus randomly placed trees. Everything is spawned at runtime through the Gazebo ROS service `spawn_sdf_model`, so no world file has to be edited by hand.

## Table of contents

1. [What it is and why it exists](#1-what-it-is-and-why-it-exists)
2. [Architecture](#2-architecture)
3. [Requirements](#3-requirements)
4. [Installation](#4-installation)
5. [Configuration](#5-configuration)
6. [Usage and expected output](#6-usage-and-expected-output)
7. [Repository layout](#7-repository-layout)
8. [Testing and verification](#8-testing-and-verification)
9. [Troubleshooting](#9-troubleshooting)
10. [Known limitations and security notes](#10-known-limitations-and-security-notes)
11. [Extending the generator](#11-extending-the-generator)

## 1. What it is and why it exists

When tuning or evaluating a steering controller for the `steer_bot` simulated robot you need a repeatable, non-trivial course. This repository provides:

- a small set of Gazebo models (cones, grass, textured ground mat) that are installed once into the local Gazebo model database;
- two SDF templates (road segment, tree) that are cloned many times at spawn time;
- `scripts/generate_track.py`, a ROS node that computes the track geometry and spawns every object.

The centre line is the curve `y = sin(x/5) * x / 2` for integer `x` in `[0, 50)`: the amplitude grows with `x`, so the track starts almost straight and ends with tight bends.

## 2. Architecture

```
            +---------------------------+
            |  scripts/generate_track.py |   rospy node "spawn_model"
            |  - centre line + spline    |
            |  - cone / road / tree poses|
            +-------------+-------------+
                          | SpawnModel service call (one per object)
                          v
         steer_bot/gazebo/spawn_sdf_model     (ROS service)
                          |
                          v
                +--------------------+        models resolved via model://
                |  Gazebo (running   | <----  ~/.gazebo/models  (cone, cone_blue, ...)
                |  with steer_bot)   | <----  standard models: asphalt_plane, oak_tree
                +--------------------+
```

Geometry algorithm (see `node()` in the script):

1. Sample the centre line at `x = 0..49`; fit a cubic spline (`scipy.interpolate.splrep`) and read its first derivative at every sample.
2. Offset each sample by `DISTANCE` (2.0 m) along the local normal. The "left" point (yellow cone) and "right" point (blue cone) are computed from the slope angle `atan(|dy/dx|)`.
3. Road: between each pair of consecutive samples the segment is cut into `ceil(dist / 0.6)` pieces; each piece is an `asphalt_plane` box of size `3 x <piece length> x 0.1` spawned at the piece start.
4. Cones are spawned at `z = 0.3`, skipping the indices in `SKIP_LEFT_POINTS` / `SKIP_RIGHT_POINTS`.
5. Trees: 40 random candidate positions in the bounding box of the centre line; a candidate is spawned only if it is more than 3 m from every cone-offset point.

## 3. Requirements

| Component | Version / note |
|---|---|
| OS | Ubuntu with ROS Noetic (Ubuntu 20.04 is the reference target) |
| Gazebo | Gazebo 11 (the Noetic default) with `gazebo_ros` and the `steer_bot` simulation running in the `steer_bot` namespace |
| Python | Python 3 with `rospy`, `gazebo_msgs`, `geometry_msgs` (from ROS), `numpy`, `scipy` |
| Gazebo models | `asphalt_plane` and `oak_tree`, downloaded automatically by Gazebo into `~/.gazebo/models` on first use (needs internet once) |

The versions above are the intended environment. The scripts were exercised here only with Python 3.10, numpy 1.26 and scipy 1.15 and a stubbed `rospy` (see section 8); Gazebo/ROS itself is **not verified in this environment**.

## 4. Installation

```bash
git clone git@github.com:lucadagati/gazebo-steer-bot-track.git
cd gazebo-steer-bot-track

# Python dependencies not shipped by ROS
python3 -m pip install numpy scipy        # or: sudo apt install python3-numpy python3-scipy

# Copy the models into the Gazebo model database (run once)
./scripts/install_models.sh
```

`install_models.sh` copies every directory under `models/` to `$GAZEBO_MODEL_DIR` (default `~/.gazebo/models`) and prints one line per model:

```
Installed cone -> /home/<you>/.gazebo/models/cone
Installed cone_blue -> /home/<you>/.gazebo/models/cone_blue
Installed cone_yellow -> /home/<you>/.gazebo/models/cone_yellow
Installed grass -> /home/<you>/.gazebo/models/grass
Installed mat -> /home/<you>/.gazebo/models/mat
Done.
```

Then start your `steer_bot` simulation (provided by the steer_bot package, not by this repository) so that the service `steer_bot/gazebo/spawn_sdf_model` exists. The cone models refer to meshes via `model://cone/...`, therefore the `cone` model must be installed even though it has no `model.config`.

## 5. Configuration

There is no config file; parameters are constants in `scripts/generate_track.py` plus one CLI flag and one environment variable.

| Name | Where | Default | Meaning |
|---|---|---|---|
| `--seed N` | CLI | none (random) | Seeds Python's `random` for tree placement, making it reproducible. Unknown arguments (ROS remappings) are ignored. |
| `GAZEBO_MODEL_DIR` | env, `install_models.sh` | `~/.gazebo/models` | Destination directory for the models. |
| `DISTANCE` | script constant | `2.0` | Lateral offset (m) of the cones from the centre line. |
| `SKIP_LEFT_POINTS` | script constant | `[24, 25]` | Left (yellow) cone indices not spawned. |
| `SKIP_RIGHT_POINTS` | script constant | `[11, 13, 39, 40, 41]` | Right (blue) cone indices not spawned. |
| `cx = np.arange(0, 50, 1)` and `cy` | `generate_trajectory()` | `sin(x/5)*x/2` | Centre-line sampling and shape. |
| `0.6` | `node()` | 0.6 m | Target road piece length. |
| `range(40)` and `> 3` | `node()` | 40 / 3 m | Number of tree candidates and minimum distance to cones. |
| service name | `spawn()` / `node()` | `steer_bot/gazebo/spawn_sdf_model` | Change it if your robot uses another namespace. |

## 6. Usage and expected output

```bash
# with the steer_bot simulation already running
python3 scripts/generate_track.py --seed 1
```

The script logs the Gazebo response status for each spawn through `rospy.loginfo` and exits when done. With `--seed 1` it issues these spawn calls (counted with a stubbed service, see section 8):

| Object | Names | Count |
|---|---|---|
| Road pieces | `roadSegment_<i>_<j>` | 192 |
| Yellow cones (left) | `pointL_<i>` | 48 (50 minus 2 skipped) |
| Blue cones (right) | `pointR_<i>` | 45 (50 minus 5 skipped) |
| Trees | `tree_<i>` | 21 with seed 1 (candidates that fall within 3 m of a cone are dropped, so the count is at most 40) |

The ground plane is not spawned by the script; use the `mat` or `grass` model in your world file if you want a textured ground. Re-running the script against the same Gazebo session will fail to spawn objects that already exist (same names); restart or reset the world first.

## 7. Repository layout

```
models/
  cone/            meshes only (cone.dae/.stl, big/blue/orange/yellow variants); no model.sdf
  cone_blue/       model.sdf + model.config, uses model://cone/cone_blue.dae
  cone_yellow/     model.sdf + model.config, uses model://cone/cone_yellow.dae
  grass/           grass ground model
  mat/             ground mat with texture (materials/, meshes/)
templates/
  road.sdf         asphalt_plane box 3 x 4 x 0.1; "<size>3 4 .1</size>" is replaced at runtime
  tree.sdf         oak_tree model
scripts/
  install_models.sh   copies models/ into $GAZEBO_MODEL_DIR or ~/.gazebo/models
  generate_track.py   ROS node that computes and spawns the track
```

Paths inside `generate_track.py` are resolved relative to the repository, so it can be launched from any working directory.

## 8. Testing and verification

There is no automated test suite. What was verified (no ROS or Gazebo available):

- `python3 -I -m py_compile scripts/generate_track.py` succeeds.
- `install_models.sh` was run with `GAZEBO_MODEL_DIR` pointing to a temporary directory and installed the five models listed in section 4.
- `generate_track.py --seed 1` was run against stub `rospy`, `gazebo_msgs` and `geometry_msgs` modules that record each `SpawnModel` call; the counts in section 6 come from that run. Output is deterministic for a given seed.

**Not verified in this environment:** actual spawning in Gazebo, mesh and material rendering, collision behaviour, and the `steer_bot` simulation. To verify on a real setup, start the simulation, run the script, and check in the Gazebo GUI that cones line both sides of a sinusoidal road; `rosservice list | grep spawn_sdf_model` should show the service.

## 9. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Script hangs on start | `rospy.wait_for_service('steer_bot/gazebo/spawn_sdf_model')` never returns: the simulation is not running or uses another namespace. Check `rosservice list`. |
| `ModuleNotFoundError: rospy` / `gazebo_msgs` | ROS environment not sourced: `source /opt/ros/noetic/setup.bash`. |
| `ModuleNotFoundError: scipy` | `python3 -m pip install numpy scipy`. |
| Cones appear without mesh / Gazebo "Unable to find uri[model://cone/...]" | Models not installed: run `./scripts/install_models.sh`, make sure `GAZEBO_MODEL_PATH` includes the destination. |
| Road or trees invisible, "model://asphalt_plane" or "oak_tree" not found | Standard Gazebo models were never downloaded; start Gazebo with internet access once or fetch them from the osrf gazebo_models repository. |
| Spawn status "Model already exists" | Objects from a previous run are still in the world. Reset or restart Gazebo. |

## 10. Known limitations and security notes

- Road pieces are spawned with the default orientation (no yaw), as boxes `3 x L x 0.1`. On the diagonal parts of the curve the road is therefore a staircase of axis-aligned boxes rather than a smooth ribbon.
- Cone positions use hard-coded skip lists tuned to the default curve; if you change the curve or `DISTANCE`, revisit them.
- Tree candidates are drawn uniformly in the bounding box of the centre line, including areas that may overlap the road edge only by the 3 m cone clearance rule.
- The script has no retries and stops on the first `ServiceException`.
- Security: the node only calls a local ROS service; it reads SDF files from the repository and executes nothing external. Do not expose the ROS master on untrusted networks.

## 11. Extending the generator

- **New track shape**: edit `generate_trajectory()` (any function of `x`); update the skip lists.
- **Different cone colours**: add a model directory under `models/` (copy `cone_blue`, point to `model://cone/cone_orange.dae`, which already exists), install, and spawn it in `node()`.
- **More obstacles**: add an SDF under `templates/`, read it with `read_file_sdf`, and call `spawn(name, x, y, z, content)`.
- **Other robot namespace**: change the service name in `spawn()` and in `node()`.
