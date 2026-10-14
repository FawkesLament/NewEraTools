# NETools message protocols

This document describes the generic **MessageProtocol v1** wire format and APIs.
Feature-specific payload schemas and topics are defined by consuming modules, not here.

## Layers

| Layer | Responsibility |
| --- | --- |
| `api/AddonMessage` | Blizzard transport: traffic-class → prefix mapping, registration, send/receive, throttle/lockdown results |
| `core/MessageProtocol` | Envelope encode/decode, validation, topic routing (no game APIs) |
| `api/MessageProtocolComm` | One-way adapter: listen/send on protocol prefixes via AddonMessage |
| Feature modules | Payload bytes, authorization, request lifecycle, business logic |

Feature modules put their own payload schemas inside the v1 envelope. Do not put business-specific topics or payload formats in this document.

Dependencies are one-way: `MessageProtocolComm` → `MessageProtocol` + `AddonMessage`. Comm does not attach methods onto the core protocol table.

## Transport prefixes and traffic classes

Blizzard throttles addon messages **per prefix**. MessageProtocolComm therefore uses two prefixes so time-sensitive traffic is not starved by control-plane chatter. Prefix strings and the traffic-class map are centralized in `api/AddonMessage.lua` (also aliased on `MessageProtocolComm`).

| Traffic class | Constant | Prefix | Use for |
| --- | --- | --- | --- |
| Realtime | `MessageProtocolComm.TrafficClass.REALTIME` | `NET_RT` | Time-sensitive messages (e.g. combat marker assignments) |
| Control | `MessageProtocolComm.TrafficClass.CONTROL` | `NET_CTL` | Non-time-sensitive messages (e.g. addon configuration checks) |

`MessageProtocolComm.Enable()` registers listeners for `NET_RT` and `NET_CTL`. Inbound bodies on either prefix are decoded as v1 envelopes and dispatched through the same topic handlers. Other addon prefixes are left alone.

If registration fails partway through, any prefixes bound in that attempt are unbound so a later `Enable()` can retry safely. Blizzard cannot unregister a prefix from the client table, but the addon callback is cleared.

`MessageProtocolComm.Send` chooses the outbound prefix from `options.trafficClass` (default **`CONTROL`** → `NET_CTL`).

## Wire format v1

```text
<version>|<type>|<topic>|<correlationId>|<payload>
```

Examples:

```text
1|E|example|-|hello
1|Q|example|a7|request_data
1|R|example|a7|response_data
1|E|example|-|
1|E|example|-|a|b|c
```

Exactly four `|` delimiters separate the envelope. Decoding finds only the first four `|` characters; every byte after the fourth delimiter is the payload, unchanged.

### Fields

| Field | Rules |
| --- | --- |
| `version` | Decimal protocol version. Supported: `1`. Independent of addon TOC version. |
| `type` | `E` event (one-way), `Q` request, `R` response. |
| `topic` | Case-sensitive id, `[A-Za-z0-9_.-]`, length 1–48. Registered by handlers in consuming code. |
| `correlationId` | `-` for events. For `Q`/`R`: `[A-Za-z0-9_-]`, length 1–24; `-` is reserved and forbidden. Responses must reuse the request's id verbatim. |
| `payload` | Opaque UTF-8/byte string owned by the feature. May be empty. May contain `\|`. Never inspected or transformed by the protocol layer. |

The complete encoded message must be ≤ 255 bytes (Blizzard addon-message limit). Null bytes (`\0`) are rejected.

### Encoding algorithm

1. Validate `type`, `topic`, and `correlationId` against the semantic rules above.
2. Treat a nil payload as `""`.
3. Concatenate the five fields with `|` (no escaping).
4. Reject if the result exceeds 255 bytes.

### Decoding algorithm

1. Reject non-strings, null bytes, and bodies longer than 255 bytes.
2. Locate the first four `|` delimiters. If fewer than four exist, reject.
3. Parse `version` as unsigned decimal digits; unsupported versions are ignored (not dispatched).
4. Validate `type`, `topic`, and `correlationId`.
5. Payload = substring after the fourth delimiter (possibly empty).

Do not use `strsplit` in a way that drops empty trailing fields or splits inside the payload.

### Semantics

- Events must use correlation id `-`.
- Requests and responses must use a non-reserved correlation id.
- Correlation for application logic is `(sender, correlationId)`; consumers must also check topic and expected responder.
- A request is not required to receive a response.
- v1 has no implicit acks, retries, timeouts, fragmentation, or queues.
- Blizzard accepting a send does **not** mean the peer received or handled it.
- Listeners receive the player's **own** outbound messages as well. Handlers must tolerate echoes (ignore, dedupe, or treat as confirmation).

## Routing and handlers

- `RegisterHandler(topic, callback)` appends a handler. Multiple handlers per topic run in registration order.
- `UnregisterHandler(topic, callback)` removes that callback only.
- Unknown topics and unsupported protocol versions are ignored.
- Each handler is invoked with `pcall`; one failing consumer does not stop the others.
- Set `MessageProtocol.debugHandlers = true` to print handler errors via `Util.Print` (default off).
- `sender` and `channel` always come from the transport event, never from the payload.
- Handlers are not told which prefix carried the message; topic + payload semantics are identical on every protocol prefix.

## Public API

### `ns.MessageProtocol` (core)

```lua
MessageProtocol.Encode(messageType, topic, correlationId, payload) -> wire|nil, reason|nil
MessageProtocol.Decode(message) -> envelope|nil, reason|nil

MessageProtocol.RegisterHandler(topic, callback)
MessageProtocol.UnregisterHandler(topic, callback)
MessageProtocol.Dispatch(message, sender, channel) -> boolean  -- used by MessageProtocolComm

MessageProtocol.debugHandlers  -- boolean; when true, log handler errors from Dispatch
```

### `ns.Api.MessageProtocolComm` (api)

```lua
MessageProtocolComm.Enable() -> ok, reason?, failedPrefix?
  -- register NET_RT / NET_CTL listeners (called from Main after modules start)
MessageProtocolComm.Send(messageType, topic, correlationId, payload, channel, targetOrOptions?, options?)
  -> ok, reason?
```

`MessageProtocolComm.PREFIX` and `MessageProtocolComm.TrafficClass` alias `ns.Api.AddonMessage.PREFIX` / `.TrafficClass`.

`Enable` returns `true` when listeners are already up or were just registered. On failure it returns `false`, a reason (`RegisterFailed` or `InvalidPrefix`), and the prefix that failed. Any prefixes bound during that attempt are unbound first.

Inbound handler argument (from `RegisterHandler`):

```lua
{
    version = 1,
    type = "E",          -- "E" | "Q" | "R"
    topic = "example",
    correlationId = "-",
    payload = "hello",
    sender = "Name-Realm",
    channel = "RAID",
}
```

`Send` failure reasons include encode errors (`invalid_type`, `invalid_topic`, `invalid_correlation_id`, `invalid_payload`, `too_large`), traffic-class errors (`InvalidTrafficClass`), channel/target errors (`InvalidChannel`, `InvalidTarget` for `WHISPER` without a target), and transport results from `AddonMessage` (for example `AddonMessageThrottle`, `AddOnMessageLockdown`).

### Minimal usage

```lua
local MessageProtocol = ns.MessageProtocol
local MessageProtocolComm = ns.Api.MessageProtocolComm

function MyFeature:OnEnable()
    MessageProtocol.RegisterHandler("my.feature.ping", function(msg)
        if msg.type ~= MessageProtocol.TYPE_EVENT then
            return
        end
        -- validate sender / authorize, tolerate own-message echoes, then use msg.payload
    end)
end

-- Default traffic class is CONTROL (NET_CTL). Prefer a single options table as the 6th argument.
local ok, reason = MessageProtocolComm.Send(
    MessageProtocol.TYPE_EVENT,
    "my.feature.ping",
    MessageProtocol.EVENT_CORRELATION_ID,
    "hello",
    "RAID"
)

-- Time-sensitive send on NET_RT:
local ok2 = MessageProtocolComm.Send(
    MessageProtocol.TYPE_EVENT,
    "my.feature.markers",
    MessageProtocol.EVENT_CORRELATION_ID,
    payload,
    "RAID",
    { trafficClass = MessageProtocolComm.TrafficClass.REALTIME }
)

-- Whisper: put target in the options table (recommended).
local ok3 = MessageProtocolComm.Send(
    MessageProtocol.TYPE_REQUEST,
    "my.feature.whisper",
    "c1",
    "ping",
    "WHISPER",
    { target = "Name-Realm" }
)
```

Legacy shape: sixth argument may be a whisper target string, with options as the seventh. If the sixth argument is a table and a seventh table is also passed, the seventh overlays the sixth (including `target` / `trafficClass`).

## Compatibility

- `AddonMessage` remains the only Blizzard transport wrapper. Prefix → traffic-class mapping must not be duplicated in feature modules.
- New sends default to `CONTROL` / `NET_CTL`. Realtime features pass `trafficClass = REALTIME`.
- Both prefixes use the same v1 wire format and topic dispatcher.
- Authorization and payload schemas remain the responsibility of each feature module.
- Prefer MessageProtocol + MessageProtocolComm for new cross-client features; do not add new per-feature addon-message prefixes.
