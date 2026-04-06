<div align="center">
  <img src="assets/images/splash.png" width="200" alt="Syncosis Logo"/>
  <h1>Syncosis: Craft Your Shared Story</h1>
  <p>A premium, real-time multiplayer digital scrapbook and canvas built with high-performance Flutter architectures.</p>
</div>

---

## Overview

**Syncosis** is a collaborative, romantic scrapbook experience designed for partners to simultaneously draw, write, drop memories, and share moments together in real-time. Built around a "shared canvas" ideology, the platform offers an incredibly smooth infinite-canvas interface using WebSocket networking.

## Core Features

### High-Performance Infinite Canvas
- **Figma-Like Rendering Engine:** Utilizes heavy GPU `ui.PictureRecorder` caching layers, separating static strokes from dynamically moving lines to effortlessly render 5,000+ strokes without dropping a single frame.
- **Buttery Smooth Scribbling:** Standard rigid connection lines are bypassed using advanced **Quadratic Bezier Splines** algorithms in the paint layer to perfectly morph your finger's path.
- **Boundless Navigation:** Interactive pan-and-zoom around an infinitely expanding virtual space using Flutter's `InteractiveViewer` combined with bounding optimizations.

### Multiplayer Network Synchronization
- **Real-Time Websocket Engine:** Instantly broadcasts strokes, items, and movements.
- **Throttled Batch Queuing:** To conserve bandwidth without losing responsiveness, micro-movement drawing deltas are batched and fired exactly every `32ms` natively over the socket hook.
- **"Live Cursor" Integration:** Keep track of where your partner's finger is located on the boundless screen just like desktop cursor sync workflows.

### Advanced Brush Mechanics
- **Multiplayer-Safe History (Undo/Redo):** Explicit architectural partitioning of the internal arrays guarantees that performing an _Undo_ only rolls back **your** strokes in reverse-local time. You will never accidentally erase your partner's masterpiece. 
- **Custom RGB Color Engine:** A slick `flutter_colorpicker` wheel to select absolute custom shades.
- **Dynamic Lineweight Selector:** A modal control that alters the mathematical spline width from razor-thin down to thick highlighter markers.

### Multimedia Scrapbooking
- **Images:** Upload standard images directly onto the canvas view utilizing Cloudinary buckets.
- **Interactive Video Chip & Post Embeds:** Convert long mp4 files or memories into styled "Polaroid" wrappers right on the main timeline.
- **Immersive Voice Notes Audio Cards:** A custom audio player renders directly on the UI tree providing live scrub bars and timestamp trackers so partners can directly drop recorded letters onto the frame.

## 🛠 Tech Stack 

- **Frontend Framework:** `Flutter` / `Dart`. 
- **Networking:** Custom Node WebSocket `wss://` backend wrapper for immediate cross-client distribution.
- **Storage/CDN Engine:** Node.js Express server acting as a Cloudinary transit layer (e.g., `CanvasUploadService`).
- **Heavy Media Handling Packages:**
  - `video_player: ^2.8.2`
  - `audioplayers: ^6.0.0`
  - `record: ^5.0.5`
  - `flutter_colorpicker: ^1.1.0`

## Getting Started

1. Check out the repository.
2. Run `flutter pub get` to pull all active plugin structures.
3. To attach locally to your device simply run:
   ```bash
   flutter run
   ```
   **Note for Production Build:** 
   ```bash
   flutter build apk --release --dart-define=SERVER_URL=https://syncosis-server-b075827ce03d.herokuapp.com
   ```
