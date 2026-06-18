# GLOSA — Example Transformations

These examples show the three stages of the GLOSA pipeline:

1. **Plain Fountain** — the screenplay as written, no annotations
2. **GLOSA-Annotated Fountain** — the same screenplay with GLOSA directives in `[[ ]]` notes
3. **Compiled Output** — the per-line instruct strings produced by `GlosaCompiler`

All source material is drawn from screenplays in the Produciesta fixtures.

---

## Example 1: The Steam Room (Scoped Intent)

Two men in a steam room, planning a murder. The emotional arc escalates from conspiratorial calm to dark resolve. This example demonstrates **SceneContext**, **scoped Intent** (precise gradient), and per-character **Constraints**.

### 1a. Plain Fountain

```fountain
INT. STEAM ROOM - DAY

BERNARD and KILLIAN (40's M) sit in a steam room, towels wrapped around their waist.

BERNARD
Have you thought about how I'm going to do it?

KILLIAN
I can't think about anything else.

BERNARD
And?

KILLIAN
Insulin. You need to give him a mega dose of the fast acting stuff.

BERNARD
Yeah, but doesn't that take a few minutes--

KILLIAN
He needs to be far enough away from anyone or anything that can help him.

BERNARD
Where would that be?

KILLIAN
When he goes running. His elevated heart rate will make the mega dose more potent.

BERNARD
He runs marathons. How am I going to keep up with him?

KILLIAN
You don't have to keep up with him. What you have to do is attract him.

BERNARD
How am I going to do that?

KILLIAN
Slutty shorts.

BERNARD
Slutty... Shorts?

KILLIAN
He buys these super-short lightweight nylon shorts online that he wears when he's jogging.

BERNARD
And you think that will do it?

KILLIAN
Oh, that will do it.

BERNARD
They turn him on?

KILLIAN
Every. Time.

BERNARD
How slutty?
```

### 1b. GLOSA-Annotated Fountain

```fountain
[[ <SceneContext location="steam room" time="morning" ambience="hissing steam, echoing tile"> ]]

[[ <Constraint character="BERNARD" direction="nervous amateur, out of his depth, trying to sound casual" ceiling="moderate"> ]]
[[ <Constraint character="KILLIAN" direction="clinical detachment, this is business, calm and methodical" ceiling="subdued"> ]]

INT. STEAM ROOM - DAY

BERNARD and KILLIAN (40's M) sit in a steam room, towels wrapped around their waist.

[[ <Intent from="conspiratorial calm" to="grim resolve" pace="slow"> ]]

BERNARD
Have you thought about how I'm going to do it?

KILLIAN
I can't think about anything else.

BERNARD
And?

KILLIAN
Insulin. You need to give him a mega dose of the fast acting stuff.

BERNARD
Yeah, but doesn't that take a few minutes--

KILLIAN
He needs to be far enough away from anyone or anything that can help him.

BERNARD
Where would that be?

KILLIAN
When he goes running. His elevated heart rate will make the mega dose more potent.

BERNARD
He runs marathons. How am I going to keep up with him?

KILLIAN
You don't have to keep up with him. What you have to do is attract him.

BERNARD
How am I going to do that?

[[ </Intent> ]]

[[ <Intent from="absurd" to="darkly comic" pace="moderate"> ]]

KILLIAN
Slutty shorts.

BERNARD
Slutty... Shorts?

KILLIAN
He buys these super-short lightweight nylon shorts online that he wears when he's jogging.

BERNARD
And you think that will do it?

KILLIAN
Oh, that will do it.

BERNARD
They turn him on?

KILLIAN
Every. Time.

BERNARD
How slutty?

[[ </Intent> ]]

[[ </SceneContext> ]]
```

### 1c. Compiled Output — `CompilationResult.instructs`

The compiler walks each dialogue line and resolves the active SceneContext, Intent (with arc position), and Constraint for that character.

| Line | Character | Arc Position | Compiled Instruct |
|------|-----------|-------------|-------------------|
| 0 | BERNARD | 1/11 (9%) | Morning in a steam room, hissing steam, echoing tile. Conspiratorial calm, very early in arc toward grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 1 | KILLIAN | 2/11 (18%) | Morning in a steam room, hissing steam, echoing tile. Conspiratorial calm, early in arc toward grim resolve, slow pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 2 | BERNARD | 3/11 (27%) | Morning in a steam room, hissing steam, echoing tile. Shifting from conspiratorial calm toward grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 3 | KILLIAN | 4/11 (36%) | Morning in a steam room, hissing steam, echoing tile. Moving from conspiratorial calm toward grim resolve, slow pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 4 | BERNARD | 5/11 (45%) | Morning in a steam room, hissing steam, echoing tile. Midway between conspiratorial calm and grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 5 | KILLIAN | 6/11 (55%) | Morning in a steam room, hissing steam, echoing tile. Past midpoint, shifting from conspiratorial calm toward grim resolve, slow pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 6 | BERNARD | 7/11 (64%) | Morning in a steam room, hissing steam, echoing tile. Well into the arc from conspiratorial calm toward grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 7 | KILLIAN | 8/11 (73%) | Morning in a steam room, hissing steam, echoing tile. Approaching grim resolve from conspiratorial calm, slow pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 8 | BERNARD | 9/11 (82%) | Morning in a steam room, hissing steam, echoing tile. Nearing grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 9 | KILLIAN | 10/11 (91%) | Morning in a steam room, hissing steam, echoing tile. Almost at grim resolve, slow pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 10 | BERNARD | 11/11 (100%) | Morning in a steam room, hissing steam, echoing tile. Arrived at grim resolve, slow pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 11 | KILLIAN | 1/7 (14%) | Morning in a steam room, hissing steam, echoing tile. Absurd, very early in arc toward darkly comic, moderate pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 12 | BERNARD | 2/7 (29%) | Morning in a steam room, hissing steam, echoing tile. Absurd, early in arc toward darkly comic, moderate pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 13 | KILLIAN | 3/7 (43%) | Morning in a steam room, hissing steam, echoing tile. Shifting from absurd toward darkly comic, moderate pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 14 | BERNARD | 4/7 (57%) | Morning in a steam room, hissing steam, echoing tile. Past midpoint between absurd and darkly comic, moderate pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 15 | KILLIAN | 5/7 (71%) | Morning in a steam room, hissing steam, echoing tile. Well into the arc from absurd toward darkly comic, moderate pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |
| 16 | BERNARD | 6/7 (86%) | Morning in a steam room, hissing steam, echoing tile. Nearing darkly comic, moderate pace. Nervous amateur, out of his depth, trying to sound casual. Ceiling: moderate. |
| 17 | KILLIAN | 7/7 (100%) | Morning in a steam room, hissing steam, echoing tile. Arrived at darkly comic, moderate pace. Clinical detachment, this is business, calm and methodical. Ceiling: subdued. |

**Key observations**:
- Lines 0-10 fall under the first scoped Intent. The resolver knows there are 11 dialogue lines, so it calculates precise gradient positions (9%, 18%, ..., 100%).
- After `</Intent>` at line 10, the first arc closes. Lines 11-17 begin the second scoped Intent with 7 lines.
- Each character's Constraint persists throughout — BERNARD stays "nervous amateur" and KILLIAN stays "clinical detachment" because no new Constraints replace them.
- The SceneContext (steam room, morning, hissing steam) prefixes every instruct.

---

## Example 2: Bernard and Sylvia (Marker Intent + Constraint Replacement)

A son tries to leave the house; his mother has other ideas. This example demonstrates **marker Intent** (no closing tag — applies forward), **Constraint replacement** mid-scene, and **neutral delivery** between Intents.

### 2a. Plain Fountain

```fountain
INT. HOME - FRONT ROOM - CONTINUOUS

He makes it almost to the front door when her voice stops him.

SYLVIA
Bernard!

BERNARD
(praying)
Yes, Satan?

He turns.

BERNARD
Oh, sorry, I thought you were someone else.

SYLVIA
What in the name of Daisy Duke are you wearing?

BERNARD
They're jogging shorts, mother.

SYLVIA
I suppose they're fine if you're into amateur urology.

BERNARD
What do you want mother?

SYLVIA
You've been using my baby oil to masturbate.

BERNARD
I haven't touched your baby oil, mother.

SYLVIA
I put a mark on the side of the bottle and there's clearly some missing.

BERNARD
You know who keeps tons of baby oil on hand?

SYLVIA
DON'T--.

BERNARD
Assisted Living facilities.

SYLVIA
I bet if I went in your bedroom right now and checked there'd be at least one sock that looks like the survivor of the Exxon Vadez oil spill.

BERNARD
Is this your way of asking me to get more while I'm out?

SYLVIA
Where are you going?

BERNARD
Why do you care, mother?

SYLVIA
(Dismissively)
You're right. I don't. Get me some baby oil. And not the scented kind that smells like it was shat out of a hippy's ass.

BERNARD
Got it. Ass-Free baby oil.
```

### 2b. GLOSA-Annotated Fountain

```fountain
[[ <SceneContext location="cluttered front room, ceramic figurines on shelves" time="pre-dawn" ambience="quiet house, distant pool filter"> ]]

[[ <Constraint character="BERNARD" direction="impatient, trying to escape, dry wit as defense mechanism" ceiling="moderate"> ]]
[[ <Constraint character="SYLVIA" direction="imperious matriarch, weaponized passive aggression, every word a power move" ceiling="intense"> ]]

INT. HOME - FRONT ROOM - CONTINUOUS

He makes it almost to the front door when her voice stops him.

[[ <Intent from="startled" to="sardonic" pace="fast"> ]]

SYLVIA
Bernard!

BERNARD
(praying)
Yes, Satan?

He turns.

BERNARD
Oh, sorry, I thought you were someone else.

SYLVIA
What in the name of Daisy Duke are you wearing?

BERNARD
They're jogging shorts, mother.

[[ </Intent> ]]

.Neutral delivery — no active Intent between the two arcs:

SYLVIA
I suppose they're fine if you're into amateur urology.

BERNARD
What do you want mother?

[[ <Intent from="accusatory" to="grudging surrender" pace="accelerating"> ]]
[[ <Constraint character="BERNARD" direction="deflecting with humor, increasingly desperate to leave" ceiling="moderate"> ]]

SYLVIA
You've been using my baby oil to masturbate.

BERNARD
I haven't touched your baby oil, mother.

SYLVIA
I put a mark on the side of the bottle and there's clearly some missing.

BERNARD
You know who keeps tons of baby oil on hand?

SYLVIA
DON'T--.

BERNARD
Assisted Living facilities.

SYLVIA
I bet if I went in your bedroom right now and checked there'd be at least one sock that looks like the survivor of the Exxon Vadez oil spill.

BERNARD
Is this your way of asking me to get more while I'm out?

SYLVIA
Where are you going?

BERNARD
Why do you care, mother?

SYLVIA
(Dismissively)
You're right. I don't. Get me some baby oil. And not the scented kind that smells like it was shat out of a hippy's ass.

BERNARD
Got it. Ass-Free baby oil.

[[ </Intent> ]]

[[ </SceneContext> ]]
```

### 2c. Compiled Output — `CompilationResult.instructs`

| Line | Character | Arc Position | Compiled Instruct |
|------|-----------|-------------|-------------------|
| 0 | SYLVIA | 1/4 (25%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Startled, early in arc toward sardonic, fast pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 1 | BERNARD | 2/4 (50%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Midway between startled and sardonic, fast pace. Impatient, trying to escape, dry wit as defense mechanism. Ceiling: moderate. |
| 2 | BERNARD | 3/4 (75%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Approaching sardonic from startled, fast pace. Impatient, trying to escape, dry wit as defense mechanism. Ceiling: moderate. |
| 3 | SYLVIA | 4/4 (100%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Arrived at sardonic, fast pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 4 | BERNARD | — | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Impatient, trying to escape, dry wit as defense mechanism. Ceiling: moderate. |
| 5 | SYLVIA | — | *(no instruct — neutral delivery, falls back to parenthetical if present)* |
| 6 | BERNARD | — | *(no instruct — neutral delivery)* |
| 7 | SYLVIA | 1/12 (8%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Accusatory, very early in arc toward grudging surrender, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 8 | BERNARD | 2/12 (17%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Accusatory, early in arc toward grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |
| 9 | SYLVIA | 3/12 (25%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Shifting from accusatory toward grudging surrender, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 10 | BERNARD | 4/12 (33%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Moving from accusatory toward grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |
| 11 | SYLVIA | 5/12 (42%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Nearing midpoint between accusatory and grudging surrender, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 12 | BERNARD | 6/12 (50%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Midway between accusatory and grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |
| 13 | SYLVIA | 7/12 (58%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Past midpoint, shifting toward grudging surrender, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 14 | BERNARD | 8/12 (67%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Well into the arc toward grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |
| 15 | SYLVIA | 9/12 (75%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Approaching grudging surrender from accusatory, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 16 | BERNARD | 10/12 (83%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Nearing grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |
| 17 | SYLVIA | 11/12 (92%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Almost at grudging surrender, accelerating pace. Imperious matriarch, weaponized passive aggression, every word a power move. Ceiling: intense. |
| 18 | BERNARD | 12/12 (100%) | Pre-dawn in a cluttered front room, ceramic figurines on shelves, distant pool filter. Arrived at grudging surrender, accelerating pace. Deflecting with humor, increasingly desperate to leave. Ceiling: moderate. |

**Key observations**:
- **Lines 5-6 have no instruct** — after `</Intent>` closes the first arc, delivery returns to neutral. These lines fall back to whatever parenthetical the screenplay provides (or no conditioning at all). Line 4 (BERNARD, "They're jogging shorts, mother.") is the last line in the first scoped intent so it still gets the SceneContext + Constraint but the Intent arc has ended.
- Wait — let me correct: Lines 4 and the scoped intent `</Intent>` closes after "They're jogging shorts, mother." So lines 5-6 are the neutral gap.
- **Constraint replacement**: BERNARD's Constraint changes from "impatient, trying to escape" to "deflecting with humor, increasingly desperate to leave" when the second Intent block begins. SYLVIA's Constraint stays the same throughout.
- **Scoped arc precision**: The second Intent spans 12 dialogue lines, so gradient positions are calculated as exact fractions (8%, 17%, 25%, ..., 100%).

---

## Example 3: Minimal — No GLOSA (Fallback Behavior)

When a screenplay has no GLOSA annotations, the compiler returns an empty instructs dictionary and the pipeline falls back to parentheticals.

### 3a. Plain Fountain (no annotations)

```fountain
INT. STEAM ROOM - DAY

BERNARD
Have you thought about how I'm going to do it?

KILLIAN
I can't think about anything else.
```

### 3b. Compiled Output

```swift
CompilationResult(
    instructs: [:],          // empty — no GLOSA annotations found
    diagnostics: [],         // no warnings
    provenance: []           // no provenance data
)
```

The pipeline falls back:

```
Line 0 → instruct = glosaInstructs[0] ?? element.instruct
                   = nil               ?? nil
                   = nil  → VoiceLockManager generates with no instruct conditioning

Line 1 → instruct = glosaInstructs[1] ?? element.instruct
                   = nil               ?? nil
                   = nil  → no conditioning
```

---

## Example 4: Marker Intent (No Closing Tag)

Marker Intents apply forward without precise line counts. The resolver estimates gradient position by interpolating against remaining lines in scope.

### 4a. GLOSA-Annotated Fountain

```fountain
[[ <SceneContext location="the CV-Link jogging trail along Riverside Drive" time="pre-dawn" ambience="distant traffic, footsteps on asphalt"> ]]

[[ <Constraint character="BERNARD" direction="winded, nervous, checking his pocket obsessively" register="mid" ceiling="moderate"> ]]
[[ <Constraint character="MASON" direction="confident runner, easy charm, flirtatious" register="low" ceiling="subdued"> ]]

EXT. THE CV-LINK ON RIVERSIDE DRIVE - EARLY MORNING

Pre-dawn. Bernard jogs awkwardly in his too-short shorts.

[[ <Intent from="anxious determination" to="panicked improvisation" pace="accelerating"> ]]

BERNARD
(to himself, between breaths)
Okay. Okay. Just... keep running.

MASON
Hey! Nice pace.

BERNARD
Thanks. I'm... training.

MASON
For what?

BERNARD
A marathon. Definitely a marathon.

MASON
You should stretch first. You're going to cramp up running like that.

BERNARD
I'll keep that in mind.

[[ </SceneContext> ]]
```

### 4b. Compiled Output

Because this Intent has a closing `</Intent>` implied by `</SceneContext>` closing the scope — but actually, the Intent here has **no closing tag**, making it a marker. The SceneContext closing terminates it. The resolver counts 7 dialogue lines between the marker and scope end.

| Line | Character | Arc Position | Compiled Instruct |
|------|-----------|-------------|-------------------|
| 0 | BERNARD | ~1/7 (14%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Anxious determination, very early in arc toward panicked improvisation, accelerating pace. Winded, nervous, checking his pocket obsessively. Register: mid. Ceiling: moderate. |
| 1 | MASON | ~2/7 (29%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Anxious determination, early in arc toward panicked improvisation, accelerating pace. Confident runner, easy charm, flirtatious. Register: low. Ceiling: subdued. |
| 2 | BERNARD | ~3/7 (43%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Shifting from anxious determination toward panicked improvisation, accelerating pace. Winded, nervous, checking his pocket obsessively. Register: mid. Ceiling: moderate. |
| 3 | MASON | ~4/7 (57%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Past midpoint between anxious determination and panicked improvisation, accelerating pace. Confident runner, easy charm, flirtatious. Register: low. Ceiling: subdued. |
| 4 | BERNARD | ~5/7 (71%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Well into the arc toward panicked improvisation, accelerating pace. Winded, nervous, checking his pocket obsessively. Register: mid. Ceiling: moderate. |
| 5 | MASON | ~6/7 (86%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Approaching panicked improvisation, accelerating pace. Confident runner, easy charm, flirtatious. Register: low. Ceiling: subdued. |
| 6 | BERNARD | ~7/7 (100%) | Pre-dawn on the CV-Link jogging trail along Riverside Drive, distant traffic, footsteps on asphalt. Arrived at panicked improvisation, accelerating pace. Winded, nervous, checking his pocket obsessively. Register: mid. Ceiling: moderate. |

**Key difference from scoped Intent**: Arc positions are prefixed with `~` to indicate they are approximate. The marker Intent doesn't know its exact span when declared — the resolver estimates by counting forward to the next Intent or scope boundary.

---

## Instruct Composition Template

The `InstructComposer` assembles instruct strings from `ResolvedDirectives` using this structure:

```
[SceneContext line]     → "{time} in {location}, {ambience}."
[Intent line]           → "{arc description}, {pace} pace."
[Constraint line]       → "{direction}. [Register: {register}.] [Ceiling: {ceiling}.]"
```

Each component is included only if active. The three lines are joined with a single space. When no directives are active, the line has no instruct entry (returns `nil` — fallback to parenthetical).

### Arc Description Templates

The arc description varies by gradient position:

| Position | Template |
|----------|----------|
| 0-10% | `"{from}, very early in arc toward {to}"` |
| 11-25% | `"{from}, early in arc toward {to}"` |
| 26-40% | `"Shifting from {from} toward {to}"` |
| 41-49% | `"Nearing midpoint between {from} and {to}"` |
| 50% | `"Midway between {from} and {to}"` |
| 51-60% | `"Past midpoint, shifting toward {to}"` |
| 61-75% | `"Well into the arc from {from} toward {to}"` / `"Well into the arc toward {to}"` |
| 76-90% | `"Approaching {to} from {from}"` / `"Nearing {to}"` |
| 91-99% | `"Almost at {to}"` |
| 100% | `"Arrived at {to}"` |

These templates are a starting point. The vocabulary is discovered empirically — which phrasings produce the best TTS output is determined through the feedback loop described in REQUIREMENTS.md Section 5.3.
