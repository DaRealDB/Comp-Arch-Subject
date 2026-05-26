# Design Spec: Modern Corporate UI for Traffic Management System

**Date:** 2026-05-22  
**Project:** City Traffic Management System (8086 Assembly)  
**Status:** Approved

## 1. Objective
Enhance the visual interface of the existing `Proj.asm` traffic controller to a "Modern Corporate" aesthetic without altering the underlying logic, timing, or state machine.

## 2. Visual Style: Modern Corporate
- **Theme:** Professional, high-contrast, industrial.
- **Color Palette (BIOS Attributes):**
    - **General Text:** Light Gray on Black (`07h`).
    - **Header:** Light Cyan on Dark Blue (`1Bh`) or White on Dark Cyan (`3Fh`).
    - **Green State:** White on Dark Green (`2Fh`).
    - **Yellow State:** Black on Dark Yellow/Brown (`60h`).
    - **Red State:** White on Dark Red (`4Fh`).
    - **Emergency:** High-intensity flashing Red background (`CFh`).

## 3. UI Components

### 3.1 Dashboard Banner
Replace current ASCII art with solid background blocks and double-line borders.
- **Borders:** Double-line (`╔`, `╗`, `═`, `║`, `╚`, `╝`).
- **Color:** Blue background banner.

### 3.2 Status Panels
Each state (Green, Yellow, Red) will be rendered inside a colored block.
- **Technique:** Use BIOS `INT 10h / AH=06h` to clear a rectangular area with a specific attribute before printing text.
- **Borders:** Single-line or Double-line box drawing characters.

### 3.3 Symbols
Replace:
- `+` with `╔` (201), `╗` (187), `╚` (200), `╝` (188).
- `-` with `═` (205).
- `|` with `║` (186).

## 4. Technical Implementation

### 4.1 BIOS Interrupts
- `INT 10h / AH=06h`: Scroll/Clear screen. Used to paint background colors for specific regions.
    - `BH`: Attribute (Background/Foreground).
    - `CH/CL`: Top-left corner.
    - `DH/DL`: Bottom-right corner.
- `INT 10h / AH=02h`: Set cursor position.
- `INT 21h / AH=09h`: Print string (standard output).

### 4.2 Code Structure
- **UI Procedures:** 
    - `DRAW_BOX`: A helper to draw a box at specific coordinates.
    - `SET_STATE_COLOR`: A procedure to update the screen colors based on the current state.
- **Data Segment:** Update strings to include extended ASCII codes for borders.

## 5. Constraints
- **Zero Logic Impact:** Delay loops and polling must remain identical.
- **Screen Size:** Fixed 80x25 characters.
- **Memory:** Must stay within the SMALL memory model limits.
