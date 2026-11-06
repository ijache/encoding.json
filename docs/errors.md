# Error handling

What the result codes mean, how to find out where a failure happened, and what a failure
leaves behind. The rest of the documentation is in the [README](../README.md).

Nothing in the public API raises, with one deliberate exception -
[the pair that returns the document](#the-one-pair-that-raises). `Marshal`, `MarshalIndent`
and `Unmarshal` all return a `TJSONResult`, and `JSONOK` is the only value that means
success:

    if JSON.Unmarshal(someJSON,somePerson) <> JSONOK then
      // ...nothing was written that you can rely on

That promise covers what the library decides. Code of yours that it calls - a property
getter or setter, a constructor, a list's `OnNotify`, a custom handler - can still raise,
and that exception is not caught: it reaches you through `Marshal` or `Unmarshal`
unchanged. Nothing is cleaned up on its way out, either. What was decoded up to that point
stays where it was written, including an instance the library built for a `nil` variable -
it is yours to free, as it is after a success.

## Result codes

| code | means |
|---|---|
| `JSONOK` | success |
| `JSONSyntax` | the bytes are not well-formed JSON — a byte the grammar does not allow at this point, or input that ran out in the middle of a value |
| `JSONTypeMismatch` | the JSON is well-formed but cannot go into the destination: either the wrong shape for it (an object for an integer, an array for a `TDictionary`, a number for a string) or a value it cannot represent (a number outside the destination's declared range, a name the enumeration does not have, text that is not a GUID or a date, an array whose length does not match a static array exactly). On encode, a value of the type that has no JSON text: a `NaN` or infinite float, a system `TColor`, a `TDateTime` outside `MinDateTime..MaxDateTime`, an enumeration or set holding a value no member is named for |
| `JSONUnsupportedType` | the Delphi type cannot be mapped at all — an array, a typed pointer, a `TList` or a `TDictionary` of something that has no JSON form (see the [Gotchas](limits-and-gotchas.md#gotchas)), or a member Delphi emits no type info for (see [Limitations](limits-and-gotchas.md#limitations)). This is a property of the *type*, so it fails the same way whatever the input says: encoding empty and `nil` values too, decoding `null` too |
| `JSONMaxDepthReached` | nesting went past `TJSONConfig.MaxDepth`, in either direction |
| `JSONError` | an internal invariant broke. It should never reach you; if one does, it is a bug in the library |

The two worth telling apart are `JSONSyntax` and `JSONTypeMismatch`: the first says the
*document* is broken, the second says the document is fine and the Delphi type you aimed it
at is the wrong one.

## Getting the detail

Every entry point takes an optional final `PJSONErrorInfo`. It costs nothing to leave out —
the record is only filled at the public boundary, and only when something failed:

    var info: TJSONErrorInfo;
    if JSON.Unmarshal(someJSON,somePerson,@info) <> JSONOK then
      writeln(format('failed at byte %d, depth %d',[info.Offset,info.Depth]));

| field | filled when | |
|---|---|---|
| `Code` | always | the same value the function returned |
| `Offset` | decoding | byte offset of the token that failed — where that token *started*, not where the reader gave up |
| `Depth` | decoding | nesting depth at that token |
| `FailedType` | encoding | the type that could not be written |
| `MemberName` | encoding | the member it came from, when the failure was inside a record or class |

For the `UnicodeString` overload of `Unmarshal` the offset is a byte offset into the UTF-8
conversion, which is not the same as a character index into the string you passed.

## The one pair that raises

The one-argument `Marshal(v)` and two-argument `MarshalIndent(v,indent)` return the document
instead of a result code, so they have nowhere to put a failure and raise `EJSONError` instead.
That is the whole difference — same encoder, same rules:

    var s := JSON.Marshal(somePerson);          // raises EJSONError on failure
    if JSON.Marshal(somePerson,s) <> JSONOK ... // returns a code, never raises

`EJSONError` carries the full `TJSONErrorInfo` in its `Info` field, so the code and the failing
member are available on the exception. They raise rather than returning `''` on purpose: an
empty string that looks like a document is exactly the silent failure the result-code API
exists to prevent.

## What is left behind after a failure

A failed `Unmarshal` into a class leaves your variable `nil`: if the library constructed the
instance, it frees it again rather than handing back a half-filled object you had no reason
to think existed. An instance **you** supplied is never freed *on a failure* — but it may
have been cleared and partly written before the failure, so it is not left untouched either.

A `TList` or `TDictionary` the library constructed takes the objects already decoded into it
along when it is freed, although neither container owns its elements. That goes **one level
deep**: an object inside a list held by the list, or inside a record held by the list, is
not freed and leaks. A list *you* supplied keeps the objects decoded into it before the
failure, and they are yours to free.

A **successful** decode of `null` into a class is the one case that does free an instance
you supplied; see [Gotchas](limits-and-gotchas.md#gotchas).
