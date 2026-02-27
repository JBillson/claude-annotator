# Claude Annotator — Implementation Scope

## The Problem

When reading a long Claude response, you often want to:
- Ask "what does this mean?" about a specific paragraph
- Say "change this to use X instead" about a code block
- Leave a note like "this doesn't match what I said earlier"

But today, you have to scroll all the way down to the input, type a message trying
to *reference* the part you mean ("in the third code block where you used forEach..."),
then scroll back up to keep reading. This completely breaks your reading flow and
makes the back-and-forth with Claude feel clunky.

## The Solution

A TUI chat client for Claude where you can **annotate responses inline** — leave
comments, questions, and edit requests directly on pieces of Claude's response as
you read, then push them all at once when you're ready.

Think of it like **Google Docs comments, but for Claude conversations**.

---

## Core Concepts

### Annotations
An annotation is a comment attached to a specific region of Claude's response.
Each annotation has:
- **Anchor**: The highlighted/selected text it's attached to
- **Content**: Your comment, question, or edit request
- **Type**: `question` | `edit` | `note`
- **Status**: `pending` (not yet sent) | `sent` | `resolved`

### Two Modes of Operation

**1. Read & Annotate Mode** (primary innovation)
- You're reading Claude's response
- Press a key to enter annotation mode at the current line/paragraph
- Type your comment inline (a small input appears right there)
- Continue reading and annotating
- When done, press a key to "push" all annotations to Claude at once

**2. Chat Mode** (standard)
- Normal back-and-forth chat at the bottom input
- Annotations from the previous response are summarized in context

### Push Behavior

When you push annotations, the system constructs a single message to Claude that
includes all your annotations with their anchored context:

```
I've reviewed your response and have the following comments:

**On this section:**
> "We should use a HashMap here for O(1) lookups..."
**[Edit]:** Actually, use a BTreeMap — I need the keys sorted.

**On this section:**
> "The function returns a Result<String, Error>..."
**[Question]:** Why not return an Option here instead? Under what
circumstances would this actually error?

**On this section:**
> "We'll deploy this to a single EC2 instance..."
**[Note]:** We're using ECS now, keep that in mind for the rest.
```

Claude receives this as a single coherent message with full context about what
each comment refers to, and responds addressing all of them.

For **edit** annotations, Claude makes the changes and presents the updated version.
For **question** annotations, Claude answers inline or at the end.
For **note** annotations, Claude acknowledges and incorporates going forward.

---

## UI Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Claude Annotator                              model: opus   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  You:                                                       │
│  Build me a REST API for managing todos                     │
│                                                             │
│  Claude:                                                    │
│  Here's a REST API implementation using Express:            │
│                                                             │
│  ```javascript                                              │
│  const express = require('express');                         │
│  const app = express();                                     │
│  ```                                                        │
│  ┌─ 📝 annotation ─────────────────────────────────────┐    │
│  │ [Edit] Use fastify instead of express               │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  For the database layer, we'll use a simple                 │
│  in-memory store:                                           │
│                                                             │
│  ```javascript                                              │
│  const todos = [];                                          │
│  ```                                                        │
│  ┌─ 📝 annotation ─────────────────────────────────────┐    │
│  │ [Question] Should we use SQLite instead for          │    │
│  │ persistence?                                         │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  The API endpoints are:                                     │
│  - GET /todos - list all                                    │
│  - POST /todos - create new                                 │
│  ...                                                        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ 2 pending annotations  [A]nnotate  [P]ush  [C]hat          │
├─────────────────────────────────────────────────────────────┤
│ >                                                           │
└─────────────────────────────────────────────────────────────┘
```

### Key UI Elements

1. **Message Stream** — scrollable area showing the conversation with annotations
   rendered inline between the paragraphs/blocks they're attached to
2. **Status Bar** — shows count of pending annotations and available keybindings
3. **Input Bar** — context-sensitive: used for chat OR annotation content depending
   on current mode
4. **Annotation Gutter** (subtle) — small markers in the left margin showing where
   annotations exist when scrolling

---

## Interaction Flow

### Reading & Annotating

```
1. Claude responds with a long message
2. User reads, scrolling through the response
3. User's cursor/focus is on a particular line or block
4. User presses `a` to annotate at that position
   → A type selector appears: [e]dit / [q]uestion / [n]ote
5. User picks a type, then the input bar activates with context
   → "Annotating lines 14-18 (code block) as [edit]:"
6. User types their comment and presses Enter
   → Annotation appears inline, collapsed to 1-2 lines
7. User continues reading, leaving more annotations
8. When done, user presses `p` to push all annotations
   → System constructs the composite message
   → Sends to Claude
   → Claude responds addressing everything
   → Annotations are marked as "sent"
```

### Reviewing Past Annotations

- Sent annotations stay visible (dimmed) so you can see what was discussed
- Resolved annotations can be collapsed/hidden with a toggle
- An annotation sidebar/list (togglable with `Tab` or `l`) shows all annotations
  for quick navigation — click one to jump to that part of the response

---

## Technical Architecture

### Recommended Stack

**Python + Textual**

Rationale:
- Built-in text selection and mouse support
- Native Markdown widget with syntax highlighting (via Rich)
- Excellent async support for streaming Claude responses
- CSS-like layout system for split panes and overlays
- Fastest path to prototype; same language as Claude's Python SDK
- Production-ready — used by Claude Code itself, Bloomberg, etc.

### Project Structure

```
claude-annotator/
├── pyproject.toml
├── src/
│   └── claude_annotator/
│       ├── __init__.py
│       ├── app.py              # Main Textual app, keybindings, screens
│       ├── api/
│       │   ├── __init__.py
│       │   ├── client.py       # Claude API wrapper (streaming, message construction)
│       │   └── models.py       # API request/response types
│       ├── chat/
│       │   ├── __init__.py
│       │   ├── conversation.py # Conversation state, branching, history
│       │   ├── message.py      # Message model (user/assistant/system)
│       │   └── annotation.py   # Annotation model and collection
│       ├── widgets/
│       │   ├── __init__.py
│       │   ├── message_view.py # Renders a single message with annotations
│       │   ├── chat_stream.py  # Scrollable list of messages
│       │   ├── annotation_inline.py  # The inline annotation display
│       │   ├── annotation_input.py   # Input for creating annotations
│       │   ├── annotation_list.py    # Sidebar list of all annotations
│       │   ├── input_bar.py    # Bottom input bar (chat + annotation modes)
│       │   └── status_bar.py   # Status bar with keybindings and counts
│       ├── composer/
│       │   ├── __init__.py
│       │   └── push.py         # Constructs the composite message from annotations
│       └── storage/
│           ├── __init__.py
│           └── persistence.py  # Save/load conversations to disk (JSON)
├── styles/
│   └── app.tcss               # Textual CSS stylesheet
└── tests/
    ├── test_annotation.py
    ├── test_composer.py
    └── test_conversation.py
```

### Data Model

```python
@dataclass
class Annotation:
    id: str                     # UUID
    message_id: str             # Which Claude message this is on
    anchor_start: int           # Start line in the rendered message
    anchor_end: int             # End line in the rendered message
    anchor_text: str            # The actual text that was highlighted
    content: str                # The user's comment
    type: Literal["question", "edit", "note"]
    status: Literal["pending", "sent", "resolved"]
    created_at: datetime
    response: str | None        # Claude's response to this annotation (if any)

@dataclass
class Message:
    id: str
    role: Literal["user", "assistant"]
    content: str                # Raw text/markdown
    annotations: list[Annotation]
    timestamp: datetime

@dataclass
class Conversation:
    id: str
    messages: list[Message]
    model: str
    system_prompt: str | None
    created_at: datetime
```

### Annotation → Message Composer

The composer is the critical piece. It takes pending annotations and constructs a
well-formatted message for Claude:

```python
class AnnotationComposer:
    def compose(self, annotations: list[Annotation]) -> str:
        """Build a single user message from all pending annotations."""
        parts = []

        # Group by type for clarity
        edits = [a for a in annotations if a.type == "edit"]
        questions = [a for a in annotations if a.type == "question"]
        notes = [a for a in annotations if a.type == "note"]

        if notes:
            parts.append("**Context notes** (keep these in mind going forward):")
            for n in notes:
                parts.append(f"\n> {n.anchor_text}\n\n{n.content}")

        if edits:
            parts.append("\n**Requested changes:**")
            for e in edits:
                parts.append(f"\n> {e.anchor_text}\n\n{e.content}")

        if questions:
            parts.append("\n**Questions:**")
            for q in questions:
                parts.append(f"\n> {q.anchor_text}\n\n{q.content}")

        return "\n".join(parts)
```

### Claude API Integration

The API is stateless — we send the full conversation history each time. This makes
annotation pushes simple: we just append the composed message as the next user turn.

```python
class ClaudeClient:
    async def send(self, conversation: Conversation) -> AsyncIterator[str]:
        """Send conversation and stream the response."""
        messages = [
            {"role": m.role, "content": m.content}
            for m in conversation.messages
        ]
        async with self.client.messages.stream(
            model=conversation.model,
            messages=messages,
            max_tokens=8192,
        ) as stream:
            async for text in stream.text_stream:
                yield text
```

---

## Keybindings

| Key | Context | Action |
|-----|---------|--------|
| `j` / `k` | Reading | Scroll down / up (line) |
| `d` / `u` | Reading | Scroll down / up (half page) |
| `a` | Reading | Start annotation at current position |
| `e` | Reading | Quick annotate as edit |
| `q` | Reading | Quick annotate as question |
| `n` | Reading | Quick annotate as note |
| `p` | Reading | Push all pending annotations |
| `Tab` | Any | Toggle annotation sidebar |
| `Enter` | Input | Send message / confirm annotation |
| `Escape` | Annotating | Cancel current annotation |
| `i` | Reading | Focus chat input (chat mode) |
| `/` | Reading | Search within response |
| `[` / `]` | Reading | Jump to prev / next annotation |
| `x` | On annotation | Delete annotation |
| `c` | On annotation | Edit annotation content |

---

## Implementation Phases

### Phase 1 — Basic Chat (1-2 days)
- Textual app skeleton with message stream and input bar
- Claude API integration with streaming
- Markdown rendering for responses
- Conversation persistence (save/load JSON)
- Basic keybindings for scrolling and input focus

### Phase 2 — Inline Annotations (2-3 days)
- Block-level navigation (move cursor between paragraphs/code blocks)
- Annotation creation flow (press `a`, pick type, write comment)
- Inline annotation rendering (displayed between content blocks)
- Annotation CRUD (create, edit, delete)
- Pending annotation counter in status bar

### Phase 3 — Push & Compose (1-2 days)
- Annotation composer (builds the structured message)
- Push flow with confirmation
- Claude responses referencing annotations
- Mark annotations as sent/resolved
- History of annotation pushes

### Phase 4 — Navigation & Polish (1-2 days)
- Annotation sidebar (togglable list with jump-to)
- Annotation gutter markers
- Search within responses
- Keyboard shortcut help overlay
- Visual polish (colors, spacing, transitions)

### Phase 5 — Advanced Features (stretch)
- Branch conversations (annotation threads that become their own conversations)
- Multi-model support (switch between Opus/Sonnet/Haiku)
- System prompt configuration
- Export conversation as markdown
- Vim-style modal editing in the input bar
- Image/file attachment support
- Token usage display and cost tracking
- Conversation search across saved sessions

---

## Key Design Decisions

### Block-Level vs Character-Level Selection

**Recommendation: Block-level selection**

Rather than trying to select arbitrary character ranges (which is fighting the
terminal), the cursor moves between logical blocks:
- Paragraphs of text
- Code blocks
- List items
- Headers

When you press `a`, the annotation anchors to the current block. This is:
- Much simpler to implement
- More natural in a terminal
- Sufficient for 90% of use cases (you rarely need to annotate half a sentence)

For the 10% case, allow the user to type a more specific reference in their
annotation (e.g., "the `forEach` on line 3 of this block").

### Single-Push vs Live-Send

**Recommendation: Batch push (with option for immediate)**

- Default: accumulate annotations, push all at once with `p`
- Optional: `Shift+Enter` on an annotation to send it immediately
- Batch pushing is better because:
  - Fewer API calls
  - Claude gets full context of all your feedback at once
  - Lets you finish reading before engaging
  - Can be smarter about grouping related annotations

### Annotation Persistence

Annotations are part of the conversation model and are saved with it. When you
load a saved conversation, annotations are restored in their positions. This means
you can close the app mid-review and come back later.

---

## Dependencies

```toml
[project]
name = "claude-annotator"
requires-python = ">=3.11"
dependencies = [
    "textual>=1.0.0",
    "anthropic>=0.40.0",
    "rich>=13.0.0",
    "pydantic>=2.0.0",
    "click>=8.0.0",         # CLI argument parsing
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0.0",
    "pytest-asyncio>=0.24.0",
    "textual-dev>=1.0.0",   # Textual devtools (CSS hot reload, console)
]
```

---

## Open Questions

1. **How should annotations interact with streaming?** If Claude is still
   streaming a response, should you be able to annotate already-rendered parts?
   (Probably yes, but the anchor positions might shift.)

2. **Should annotations on code blocks be smarter?** e.g., automatically
   include the language and surrounding context when composing the push message.

3. **How verbose should the push message be?** Should it include the full
   anchor text or just enough for Claude to identify the section?

4. **Do you want conversation branching as a separate feature?** The scope above
   treats annotations as a linear "review then push" flow. Full branching
   (separate conversation threads per annotation) is Phase 5 / stretch.

5. **Should there be a way to annotate your OWN messages?** e.g., "actually I
   meant X here" — correcting yourself before Claude responds.
