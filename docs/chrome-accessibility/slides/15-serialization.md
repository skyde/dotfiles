---
module: Serialization and AXMode
part: Part IV - The Chromium pipeline
---

## AXNodeData: the wire format for one node

Everything the browser process knows about a node arrives as an `AXNodeData`. It
is designed to be sparse: over 100 possible attributes, 5-10 set on a typical
node.

```cpp
struct AXNodeData {
  AXNodeID id;
  ax::mojom::Role role;
  uint32_t state;                       // bitfield of ax::mojom::State
  uint64_t actions;                     // bitfield of ax::mojom::Action
  std::vector<std::pair<ax::mojom::StringAttribute, std::string>> string_attributes;
  std::vector<std::pair<ax::mojom::IntAttribute, int32_t>> int_attributes;
  std::vector<std::pair<ax::mojom::FloatAttribute, float>> float_attributes;
  std::vector<std::pair<ax::mojom::BoolAttribute, bool>> bool_attributes;
  std::vector<std::pair<ax::mojom::IntListAttribute, std::vector<int32_t>>> intlist_attributes;
  std::vector<AXNodeID> child_ids;
  AXRelativeBounds relative_bounds;
};
```

KEY: Mandatory fields are tiny; everything else is a key/value pair that only exists when it is not the default. That is what makes caching an entire page affordable.

## The attribute families

Six enums in `ax_enums.mojom`, each with dozens of members. A sample of what
lives where:

| Family | Examples |
| --- | --- |
| `StringAttribute` | `kName`, `kDescription`, `kValue`, `kPlaceholder`, `kUrl`, `kLanguage`, `kHtmlTag`, `kAriaBrailleLabel` |
| `IntAttribute` | `kNameFrom`, `kDescriptionFrom`, `kHierarchicalLevel`, `kPosInSet`, `kSetSize`, `kCheckedState`, `kRestriction`, `kTextDirection` |
| `FloatAttribute` | `kValueForRange`, `kMinValueForRange`, `kMaxValueForRange`, `kFontSize` |
| `BoolAttribute` | `kLiveAtomic`, `kBusy`, `kModal`, `kSelected`, `kClipsChildren` |
| `IntListAttribute` | `kLabelledbyIds`, `kDescribedbyIds`, `kControlsIds`, `kCharacterOffsets`, `kWordStarts`, `kWordEnds` |
| `StringListAttribute` | custom action descriptions, and similar lists |

REF: Reading `ax_enums.mojom` end to end is the single highest-value hour a new Chromium accessibility engineer can spend.

## AXTreeUpdate: the wire format for a change

```cpp
struct AXTreeUpdate {
  AXTreeData tree_data;                 // whole-tree facts: title, url, focus
  AXNodeID root_id;
  std::vector<AXNodeData> nodes;        // any order
  ax::mojom::EventFrom event_from;
  ax::mojom::Action event_from_action;
  std::vector<AXEventIntent> event_intents;
  std::optional<AXTreeChecks> tree_checks;
};
```

Two jobs, one struct:

- A **complete tree**: every node exactly once, no duplicates, every node either
  the root or somebody's child. Order does not matter.
- An **incremental change**: only the nodes that changed. To insert, add the node
  and update the parent's `child_ids`. To remove, drop it from `child_ids`.

WATCH: An `AXTreeUpdate` used incrementally is *stateful* - it only makes sense against the exact tree the sender believed the receiver had. This is why the serializer must track what it has sent.

## AXTreeSerializer

A template class that knows nothing about accessibility semantics. It walks a
tree source and produces valid incremental updates.

```cpp
template <typename AXSourceNode, typename AXSourceNodeVectorType,
          typename AXTreeUpdateType, typename AXTreeDataType,
          typename AXNodeDataType>
class AXTreeSerializer {
  void Reset();
  bool SerializeChanges(AXSourceNode node, AXTreeUpdateType out_update, ...);
  void MarkNodeDirty(AXNodeID id);
  void MarkSubtreeDirty(AXNodeID id);
  bool IsInClientTree(AXSourceNode node);
  void set_max_node_count(size_t);
  void set_timeout(base::TimeDelta);
};
```

Its requirements of the source tree are minimal: unique positive integer IDs, no
cycles, and a notification when a node's data or child list changes.

KEY: The serializer is the reusable core. Blink, Views, PDF, and the automation API all feed different sources into the same class.

## The client tree

The serializer's secret is that it keeps a mirror: `ClientTreeNode`, its model of
what the receiver already knows.

- A node it has never sent gets serialized in full.
- A node it has sent and that is not dirty gets skipped entirely.
- When the structure changes, it computes the **least common ancestor** of the
  source and client views and re-serializes from there, so the update is always
  self-consistent.

If the source tree misbehaves - duplicate IDs, mutation during serialization -
`SerializeChanges()` returns false and calls `Reset()`, so the next update
resends the entire tree.

WHY: This design means a buggy source can lose updates but can never corrupt the client tree into an invalid state. That is a deliberate safety property, and it is why crash-on-error is opt-out rather than the only behavior.

## AXTreeSource: the interface Blink implements

```cpp
// ui/accessibility/ax_tree_source.h - conceptually
AXSourceNode GetRoot() const;
AXSourceNode GetFromId(AXNodeID) const;
AXNodeID GetId(AXSourceNode) const;
void CacheChildrenIfNeeded(AXSourceNode);
void GetChildren(AXSourceNode, AXSourceNodeVectorType* out) const;
AXSourceNode GetParent(AXSourceNode) const;
bool IsValid(AXSourceNode) const;
void SerializeNode(AXSourceNode, AXNodeDataType* out) const;
```

`BlinkAXTreeSource` implements this over `AXObject`, mapping each call onto
Blink's tree walk and onto `AXObject::Serialize()`.

TRY: Read `blink_ax_tree_source.cc` alongside `ax_tree_serializer.h`. The seam between "knows about the web" and "knows about trees" is exactly here, and it is unusually clean for a codebase this old.

## Batching and when serialization runs

Serialization does not happen when the DOM changes. It happens after the document
lifecycle is clean, batched.

1. Blink code calls `AXObjectCacheImpl::Handle*` - the change is **deferred**.
2. After style and layout are clean, `CommitAXUpdates()` runs - in parallel with
   GPU rendering, roughly at frame cadence.
3. The tree is finalized, frozen, and serialized.
4. `RenderAccessibilityImpl` sends the batch over Mojo.

Nothing is serialized while layout is dirty, because the answers would be wrong
or the code would crash on a DCHECK.

KEY: Accessibility work is frame-paced. That is why "one attribute change" and "a thousand attribute changes in the same task" cost nearly the same.

## The mode flags

`ui::AXMode` is a bitmask that decides how much of this work happens at all.

```text
kNativeAPIs        1<<0   a platform client is attached
kWebContents       1<<1   build a tree for web contents at all
kInlineTextBoxes   1<<2   line boxes + character offsets
kExtendedProperties 1<<3  screen-reader-grade attributes, table info, live regions
kHTML              1<<4   every HTML attribute (expensive, memory-hungry)
kHTMLMetadata      1<<5   <head> metadata, snapshot only
kLabelImages       1<<6   automatic image annotations
kPDFPrinting       1<<7   enough to export a tagged PDF
kAnnotateMainNode  1<<8   annotate the main node
kFromPlatform      1<<9   meta-flag: this bundle came from a platform interaction
kScreenReader      1<<10  a known screen reader is present
kNativeAdaptedWebContents 1<<11  serialize for a native UI wrapper
```

REF: `ui/accessibility/ax_mode.h`. The `LINT.IfChange` comment there lists every file that must be updated together when a flag is added - including the histogram enums.

## The mode bundles

Named combinations, used throughout the codebase:

```cpp
kAXModeBasic            = kNativeAPIs | kWebContents;
kAXModeWebContentsOnly  = kWebContents | kInlineTextBoxes | kExtendedProperties;
kAXModeComplete         = kNativeAPIs | kWebContents | kInlineTextBoxes
                        | kExtendedProperties;
kAXModeInspector        = kWebContents | kInlineTextBoxes | kExtendedProperties
                        | kScreenReader;
kAXModeFormControls     = kNativeAPIs | kWebContents, filter: kFormsAndLabelsOnly;
kAXModeOnScreen         = kNativeAPIs | kWebContents | kInlineTextBoxes
                        | kExtendedProperties, filter: kOnScreenOnly;
kAXModeDefaultForTests  = complete + kHTML + kScreenReader;
```

Note the *filter flags*, a second bitfield: `kFormsAndLabelsOnly` and
`kOnScreenOnly` prune the tree rather than adding attributes.

WATCH: Tests default to a mode that includes `kScreenReader`, which builds the whole tree. Production without a screen reader gets a pruned tree. A test-only bug can hide here in both directions.

## Modes change behavior, not just cost

This is the subtle part that bites people.

- Without `kInlineTextBoxes`, a text field still exposes its value but not the
  line structure - so "read by line" degrades.
- Without `kExtendedProperties`, text style attributes, table cell details, live
  region properties, and relationship attributes are absent, plus the HTML tag,
  ID, and class.
- With `kScreenReader` off, Chromium is free to prune nodes that only a screen
  reader would care about.
- `AXMode::kFromPlatform` marks bundles that were turned on because a platform
  integration asked, so Chromium can selectively suppress modes that would
  otherwise be forced on by an automation client.

KEY: "Works with a screen reader, broken for our automation tool" is usually a mode difference, not a tree bug.

## Serializing across frames

Each frame serializes independently. Stitching happens in the browser.

- An iframe's node in the parent tree carries the child's `AXTreeID`, written by
  `AXObject::SerializeChildTreeID()`.
- The browser keeps a map from `AXTreeID` to tree, plus the reverse (a tree root
  back to its parent node).
- Node IDs collide freely across frames; only the (tree ID, node ID) pair is
  meaningful.

```text
[main frame tree]  iframe node -> childTreeId = 5f2a...
                                       |
[child frame tree] rootWebArea (its own ids, starting again at 1)
```

TRY: Load a page with a cross-origin iframe, dump the tree from `chrome://accessibility`, and find the child tree ID on the iframe node. Then dump the child frame and match it up.

## Snapshots versus streaming

Two different jobs, same machinery.

- **Streaming** - the normal case. The serializer keeps its client tree and sends
  deltas forever.
- **Snapshot** - a one-shot complete tree, used for PDF export, Android's
  freeze-dried tabs, "distill this page", and assorted browser features.

Snapshots are what `set_max_node_count()` and `set_timeout()` exist for: a
snapshot of a pathological page must terminate, even if the result is truncated.
The serializer stops walking children but still produces a *consistent* tree.

WHY: A truncated-but-valid tree is far better than a hang. The invariant "never emit an invalid update" is preserved even under the limits.

## Failure modes and their fingerprints

What goes wrong here, and how it looks in a bug report:

- **Missing `Handle*` call** - tree correct on load, stale after interaction.
- **Node marked dirty but not its parent** - a new child never appears, because
  the parent's `child_ids` was never re-serialized.
- **Duplicate or reused IDs** - serializer resets and resends the whole tree,
  visible as periodic latency spikes and `AXSerializationErrorFlag`s.
- **Mutation during serialization** - forbidden by the frozen state; shows up as
  a DCHECK in `AX_FAIL_FAST_BUILD` builds.
- **Mode mismatch** - attributes missing for one client and present for another.

REF: `ui/accessibility/ax_error_types.h` defines the serialization error flags, and `AXTreeChecks` in an update carries consistency data the receiver can validate against.
