# encoding.json
encoding.json is a library for Delphi that uses RTTI and generics to encode/decode JSON-data into/from Delphi types.

Why another JSON library: see [Motivation](#motivation). This repo [contains AI-generated code](#slop).

Licensed under the [zlib license](LICENSE) — free for any use, commercial applications included.

## Installation
The library comes as a single file. Just drop the file `encoding.json.pas` into your project.

**Tested on:** Delphi 12 Athens, Win32 and Win64 - the whole suite, on both, by
`runtests.bat`. Nothing else is tested: other Delphi versions and the macOS, iOS, Android and
Linux targets may well work, but I haven't compiled the unit for them, let alone run it.

## Basic usage

`JSON` is a ready-made global instance. Everything below is a method **on that instance**,
not a class method.

To encode, use either:

    JSON.Marshal( myRecordObjectOrArray , myString );

or, if you want pretty-printing:

    JSON.MarshalIndent( myRecordObjectOrArray , '<indent>', myString );

To decode, just:

    JSON.Unmarshal( myJsonString, myRecordObjectOrArray );

The string can be a `UnicodeString` or a `UTF8String` in either direction. `Unmarshal` also
takes a `PAnsiChar` and a length, so a buffer can be decoded without copying it into a
string first.

Consider this structure:

    TPerson = record
        FirstName: string;
        LastName: string;
    end;

To encode an item of this structure to JSON, just:

    uses encoding.json

    ...

    var somePerson: TPerson;
    somePerson.FirstName:= 'John';
    somePerson.LastName:= 'Lennon';

    var someJSON: UTF8String;

    JSON.Marshal(somePerson,someJSON);
    // someJSON is now {"FirstName":"John","LastName":"Lennon"}

Every entry point returns a result code rather than raising — see
[Error handling](#error-handling). For the cases where a result code is more
ceremony than the call is worth, `Marshal` and `MarshalIndent` also come as
one-argument functions that return the document and raise `EJSONError` if it cannot
be produced:

    Send( JSON.Marshal(somePerson) );
    writeln( JSON.MarshalIndent(somePerson,'  ') );


## Error handling

Nothing in the public API raises, with one deliberate exception: the `Marshal` and
`MarshalIndent` overloads above that return the document. Everything else returns a
`TJSONResult`, and `JSONOK` is the only value that means success:

    if JSON.Unmarshal(someJSON,somePerson) <> JSONOK then
      // ...nothing was written that you can rely on

What each code means, how to get the byte offset or the failing member, and what a failed
decode leaves behind in your variable are in [docs/errors.md](docs/errors.md).


## Configuration

The global `JSON` instance is created with `JSONDefaultConfig`. Settings live in a
`TJSONConfig`, which you can pass to the constructor of your own instance or hand to
`Configure`:

    var cfg := JSON.Config;          // start from what is already there
    cfg.DateTimeFormat := jdfEpoch;
    cfg.SortKeys := true;
    JSON.Configure(cfg);

`Configure` is **not thread-safe** — call it before the instance is shared. Every setting,
how to create an instance of your own, and the rules for key order and dates are in
[docs/configuration.md](docs/configuration.md).


## Features
- Supports all simple types: `Integers, Floats, Strings, Booleans`
- Supports `Classes` and `Records`, will encode/decode all publicly visible fields (and properties, in case of classes).
  A property counts in the direction it supports: a read-only one is encoded and never
  decoded, a write-only one is decoded and never encoded. The exception is a property of
  class type: it is decoded into the instance its getter returns, read-only or not, and
  its setter is not called - so `property Items: TObjectList<T> read FItems` round-trips.
  The setter is only used when the getter returns `nil`, and for `null`.
- Supports generic types `TList<T>, TDictionary<K,V>` and its descendants. A JSON key is
  text, so `K` is a `string`, `AnsiString`, `UTF8String` or `WideString`; any other key
  type - a `ShortString` included - is refused with `JSONUnsupportedType`
- Special support for `TStringList` to handle both lists of strings as well as key-value-maps
- `TColor` encodes as a web colour, `"#rrggbb"` — the byte order is swapped, because Delphi
  stores `$00bbggrr`
- Support for `TGUID`, written in lower case as RFC 4122 asks, read in either case
- `char`, `AnsiChar` and `WideChar` encode as a one-character string
- `Sets` over an enumeration encode as an array of member names. Decoding is deliberately
  forgiving: `null` and `[]` both mean the empty set, and a member named twice is not an
  error
- `TDateTime`, `TDate` and `TTime` encode as RFC 3339, unix epoch seconds or epoch
  milliseconds; whether a value in memory is UTC or local time is a
  [config-parameter](docs/configuration.md#dates-and-times)
- `Currency` is written exactly, from its scaled integer, not through a float
- `Pointer` types for all types mentioned above are supported
- **[Dynamic documents](docs/dynamic-documents.md)** (experimental): a `Variant` destination accepts any
  JSON, whatever its shape - objects become a `TVarDict` reached by name, arrays a native
  variant array
- Rename, skip or omit-empty attribute `[JSON]`
- [Custom parsers and formatters](docs/custom-handlers.md) for any type, replacing a
  built-in or building on one
- Single-Line decoding/encoding, with `Marshal`/`MarshalIndent` overloads that return the
  document for use as an expression
- Single-File
- Light on heap allocations
- [Result codes](docs/errors.md) instead of exceptions, with optional detail (offset,
  depth, failing member)
- 224 DUnitX tests, plus every file of the
  [JSONTestSuite](https://github.com/nst/JSONTestSuite) conformance corpus as a case of its
  own, and the 95 files that must be accepted once more through a `Variant` - 637 in all


## Limits and gotchas

Some behaviour could reasonably have gone the other way, and a few things Delphi's RTTI
does not allow at all. Both are listed in
[docs/limits-and-gotchas.md](docs/limits-and-gotchas.md) - worth a read before one of them
surprises you.

## Motivation
For quite some time I really wanted something like the encoding/json-package from Go (https://pkg.go.dev/encoding/json) in Delphi. Precisely, I was looking for something simple, worry-free. Neither would it be necessary to be super-performant, nor would it need to support every edge case. Decoding/encoding should work with a single line of code and it shouldn't be mandatory to amend your types to make them work with the library.

While there are existing solutions - like the excellent mORMot and Grijjy libraries, not to forget the built-in `REST.Json` unit - each of those had some drawbacks I did not like:

- Some are embedded in bigger frameworks/libraries and increase the amount of dead weight you have to carry in your project.
- You mostly see a focus on classes, less on records and the rest of Delphi's type system.
- Some require you to make your types "fit" the encoder/decoder.

I thought there is room for another take on this topic that addresses exactly these points:

- It's a single file you can drop into your project.
- It covers all of the important cases/types.
- There are attributes, but they're optional.

On top of that there were a couple of other things on my wishlist:

- I want to have good test-coverage, so I have a high confidence this stuff works.
- I want to have the TStrings/TStringList/TDictionary/TList types directly supported.

## Slop!?

Since people tend to fight over this: yes, this repo contains AI-generated code. I worked on the library in the little spare time I have, until at some point it turned into a total rabbit hole (as it always does - in this case, correctness and completeness). I had a working library, but a much weaker one than what's here now. I heavily used Claude Opus 5.5 to turn it into what it is now.



## License

[zlib](LICENSE). Fork it, copy it, change it, ship it inside commercial products — there
is nothing to sign and nothing to pay. All it asks is that you do not claim you wrote the
original, that modified versions say they are modified, and that the notice stays in the
source.

The single file carries the full notice in its header, which is the copy that matters: the
unit is meant to be dropped into a project on its own, and a repository `LICENSE` does not
travel with it.

The test data in `testdata/` is not covered by it: it comes from three other projects and
keeps their licenses, MIT and BSD-3-Clause — see [testdata/README.md](testdata/README.md).


## Support

**Not a condition of the license.** encoding.json is free for any use, and nothing is
withheld from you if you skip this section entirely.

That said, if it saves you time in something you sell, either an acknowledgment in your
documentation or a donation of whatever you think it is worth would be appreciated:

- [GitHub Sponsors](https://github.com/sponsors/ijache)
- [Ko-fi](https://ko-fi.com/ingojache)
