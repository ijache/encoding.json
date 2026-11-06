# Dynamic documents

Decoding JSON you have no type for, reading and building it through a `Variant`. The rest
of the documentation is in the [README](../README.md).

**Experimental.** Dynamic documents work and are tested, but their limits are of a kind the
rest of the library avoids - a write through a nested path is silently lost, and keys
cannot be listed - so they may still change in a later version without counting as a
breaking change.

For a document you have no type for, decode into a `Variant`. Every JSON shape has a
landing place: an object becomes a `TVarDict`, an array becomes a native variant array,
and a scalar becomes the matching variant subtype. A number decides by its notation: `42`
becomes an `Int64` and `1.5` or `1e2` a `double` - and so does a whole number too large for
an `Int64`, such as `18446744073709551615`, as in Go.

It is made for documents whose keys you know - a config, the part of an API response you
care about - rather than for exploring one you know nothing about. Two things it cannot do
yet:

- **List the keys.** There is no way to ask a `TVarDict` what it holds, only whether a
  given key is there.
- **Reach a key that is not a Delphi identifier.** Members are reached through late
  binding, so `content-type`, `@odata.context` or `$ref` cannot be named. They are decoded
  and encoded again unharmed, but cannot be read or written in between.

For either, decode into a `TDictionary<string,...>` or a record instead.

## Reading

    var doc: Variant;
    JSON.Unmarshal(someJSON, doc);

    if VarIsDict(doc) then
      Writeln(string(doc.user.name));      // members by name, exactly as written
    if VarIsArray(doc) then
      Writeln(string(doc[0]));

Members are reached by name through late binding, nested to any depth. A member holding an
array is a plain variant array, so lift it out and index it:

    var items: Variant := doc.items;
    Writeln(string(items[0].label));

A key that was never there reads as `Unassigned`, and one that holds JSON `null` reads as
`Null` - so "absent" and "explicitly nothing" stay tellable apart:

    if VarIsEmpty(doc.maybe) then ...      // no such key
    if VarIsNull(doc.maybe) then ...       // "maybe": null

## Building

Build one from nothing with `VarDictCreate`, and write it back out with `Marshal` like anything
else:

    var doc := VarDictCreate;
    doc.name := 'Ada';
    doc.tags := VarArrayOf([1, 2, 3]);
    JSON.Marshal(doc, s);

## Keys

Keys are matched **exactly** and stored as they arrived. Unlike record members - which fall
back to a case-insensitive match against their declared names - a document has no declared
names for an incoming key to be matched against, so the key is simply the data.
`{"a":1,"A":2}` is a two-member object and stays one.

A consequence worth knowing: a key read with the wrong casing is just a key that is not
there, and reads back as `Unassigned` rather than raising.

**Order.** A `TVarDict` does not keep the order its keys arrived in. They are written out
sorted, so the output is predictable, but a document's original key order does not
survive a round trip.

## Assignment copies the whole document

`b := a` gives you an independent tree, all the way down. Two consequences worth knowing:

Passing a document to a function **by value copies all of it**, so take it as `const` or
`var`:

    procedure Handle(const doc: Variant);   // not: procedure Handle(doc: Variant)

And a write through a nested path does not stick, because the intermediate hands back a
copy:

    doc.inner.x := 2;                       // compiles, runs, silently discarded

Read, modify, write back instead:

    var inner := doc.inner;
    inner.x := 2;
    doc.inner := inner;                     // this one sticks

That is the price of value semantics; the two cannot both be had in Delphi's variant
model. On the other hand a document can never contain itself, so there are no cycles to
worry about.
