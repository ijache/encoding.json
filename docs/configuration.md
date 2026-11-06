# Configuration

Every setting, what it does, and the rules behind key order and dates. The rest of the
documentation is in the [README](../README.md).

The global `JSON` instance is created with `JSONDefaultConfig`. Settings live in a
`TJSONConfig`, which you can pass to the constructor of your own instance or hand to
`Configure`:

    var cfg := JSON.Config;          // start from what is already there
    cfg.DateTimeFormat := jdfEpoch;
    cfg.SortKeys := true;
    JSON.Configure(cfg);

## Settings

| field | default | |
|---|---|---|
| `MaxDepth` | `64` | nesting limit for both directions. `<= 0` means the default |
| `DateTimeFormat` | `jdfRFC3339` | or `jdfEpoch` / `jdfEpochMillis` |
| `DateTimeIsUTC` | `true` | whether a `TDateTime` in memory holds UTC, or local time to be converted |
| `DetectKeyValuePairs` | `true` | whether a `TStrings` whose entries *all* look like `name=value` is written as an object |
| `SortKeys` | `false` | encode only: emit a record's or an object's members in sorted order instead of declaration order |
| `LineBreak` | `#10` | the break `MarshalIndent` writes between lines; ignored without an indent |

Indentation is **not** a setting. It is an argument to `MarshalIndent`, because `Configure`
is not thread-safe and the global `JSON` instance is shared - there would be no safe way to
ask a shared instance for one pretty document. `LineBreak` stays a setting because it is a
property of the machine or the consumer, not of the individual call.

## An instance of your own

A library of your own wants its own instance rather than reconfiguring the global one
behind its host's back. `TJSONCodec.Create` takes the config and has no parameterless form, so
start from `JSONDefaultConfig`:

    var cfg := JSONDefaultConfig;
    cfg.MaxDepth := 64;
    var myJSON := TJSONCodec.Create(cfg);

`Configure` is **not thread-safe** — call it before the instance is shared. Once it is
configured, marshalling on several threads at once is fine.

## Key order

`SortKeys` affects encoding only, and it sorts by the name that actually goes on the wire -
the `[JSON('name')]` attribute where there is one, the member name otherwise. The order is
ordinal over the name - `CompareStr`, compared code unit by code unit - and it is
deliberately not locale-aware: the same value has to encode to the same document on every
machine. Two members that end up with the same name keep their declaration order.
Decoding never cares what order the keys arrived in, with or without this setting.

A dictionary's keys - a `TDictionary` and a `TVarDict` alike - are **always** written
sorted, by exactly the same rule, whatever `SortKeys` says. A dictionary has no order of
its own, only the order of its hash table, which would make the same dictionary encode
differently from one Delphi version to the next. Go sorts its map keys for the same
reason.

## Dates and times

Decoding a date goes by the token, not by `DateTimeFormat`: a string is read as ISO 8601
and a number as an epoch, so changing the setting does not orphan existing documents. The
setting still decides whether a number means seconds or milliseconds.

The wire is always **UTC**, written with a `Z`. A `TDateTime` carries no zone, so
`DateTimeIsUTC` tells the library what yours hold. By default it is `true`, as in
REST.Json: a value is taken to be UTC already and nothing is converted. Set it to `false`
and a value is local time - converted to UTC on the way out and back to local on the way
in. Text carrying an explicit offset (`+02:00`) decodes correctly either way - the reader
goes by what the token says - and text with no zone at all is read as UTC.

`TDate` and `TTime` encode exactly like a `TDateTime`. Decoding into one keeps only the
date, or only the time of day, of whatever arrives - cut in the zone the value is held in.
