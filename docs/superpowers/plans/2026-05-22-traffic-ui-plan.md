# Modern Corporate UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the Traffic Management System UI from simple text to a "Modern Corporate" aesthetic using BIOS color attributes and box-drawing characters, while maintaining all original logic.

**Architecture:** 
- **Data-Driven UI:** Update the strings in the `.DATA` segment with box-drawing characters.
- **Color Injection:** Integrate BIOS `INT 10h / AH=06h` and `AH=09h` calls into the existing state machine logic to apply contextual background and foreground colors.
- **Stateless Procedures:** Add modular UI helper functions for box drawing and color application.

**Tech Stack:** 8086 Assembly (TASM/EMU8086 compatible), BIOS Video Interrupts (INT 10h), DOS System Interrupts (INT 21h).

---

### Task 1: Update Data Segment Strings

**Files:**
- Modify: `Proj.asm` (Data Segment)

- [ ] **Step 1: Replace simple border characters with Box-Drawing characters.**

Update `BNR_TOP`, `BNR_BOT`, `G_TOP`, `Y_TOP`, `R_TOP`, etc., to use double-line borders.

```assembly
    ; --- Updated Banner (Example) ---
    BNR_TOP     DB  201, 41 DUP(205), 187, 13, 10, '$' ; ╔════...╗
    BNR_TIT     DB  186, '   CITY TRAFFIC MANAGEMENT SYSTEM v1.0  ', 186, 13, 10, '$'
    BNR_BOT     DB  200, 41 DUP(205), 188, 13, 10, '$' ; ╚════...╝
```

- [ ] **Step 2: Save and verify compilation.**

Run: `tasm Proj.asm` (or equivalent) to ensure no syntax errors in the new string definitions.

---

### Task 2: Implement UI Helper Procedures

**Files:**
- Modify: `Proj.asm` (Code Segment)

- [ ] **Step 1: Add `SET_RECT_COLOR` procedure.**

This procedure uses `INT 10h / AH=06h` to paint a specific screen region with a color attribute.

```assembly
; INPUT: CH/CL = top-left, DH/DL = bottom-right, BH = attribute
SET_RECT_COLOR PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    MOV AH, 06h
    MOV AL, 0
    INT 10h
    POP DX
    POP CX
    POP BX
    POP AX
    RET
SET_RECT_COLOR ENDP
```

- [ ] **Step 2: Add `SET_CURSOR` helper.**

```assembly
; INPUT: DH = row, DL = column
SET_CURSOR PROC
    PUSH AX
    PUSH BX
    MOV AH, 02h
    MOV BH, 0
    INT 10h
    POP BX
    POP AX
    RET
SET_CURSOR ENDP
```

---

### Task 3: Apply Theme to Dashboard and States

**Files:**
- Modify: `Proj.asm` (Main Loop and State Blocks)

- [ ] **Step 1: Update `SHOW_BANNER` to use colors.**

Set the banner background to Dark Blue (`1Fh`).

```assembly
SHOW_BANNER PROC
    ; Paint banner area (Rows 0-3)
    MOV BH, 1Fh ; Blue background, White text
    MOV CH, 0
    MOV CL, 0
    MOV DH, 3
    MOV DL, 79
    CALL SET_RECT_COLOR
    
    ; Reset cursor to 0,0
    MOV DH, 0
    MOV DL, 0
    CALL SET_CURSOR
    
    ; Existing print logic...
    LEA DX, BNR_TOP
    MOV AH, 09h
    INT 21h
    ; ... (rest of SHOW_BANNER)
    RET
SHOW_BANNER ENDP
```

- [ ] **Step 2: Apply contextual colors to Traffic States.**

In `MAIN_LOOP`, before printing state strings, paint the status area (Rows 6-10).
- **Green:** `2Fh` (Dark Green)
- **Yellow:** `60h` (Dark Yellow/Brown)
- **Red:** `4Fh` (Dark Red)

---

### Task 4: Enhance Emergency Override UI

**Files:**
- Modify: `Proj.asm` (DO_OVERRIDE Handler)

- [ ] **Step 1: Update Flash Logic.**

Change the flashing logic to use high-intensity Red (`CFh`) instead of just printing text.

```assembly
; Inside FLASH_LOOP:
    MOV BH, 0CFh ; Flashing Red Background
    MOV CH, 12
    MOV CL, 10
    MOV DH, 14
    MOV DL, 70
    CALL SET_RECT_COLOR
```

---

### Task 5: Final Validation

- [ ] **Step 1: Visual Inspection.**
Run the program in EMU8086 or TASM and verify:
- Banner is Blue.
- Borders are seamless.
- State panels change color appropriately.
- Logic/Timing is unchanged.

- [ ] **Step 2: Commit changes.**

```bash
git add Proj.asm docs/superpowers/specs/2026-05-22-traffic-ui-design.md docs/superpowers/plans/2026-05-22-traffic-ui-plan.md
git commit -m "feat: implement modern corporate UI for traffic controller"
```
