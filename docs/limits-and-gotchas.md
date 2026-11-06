# Limits and gotchas

What encoding.json does that you might not expect, and what it cannot do at all. The
rest of the documentation is in the [README](../README.md).

## Gotchas

Decisions that could reasonably have gone the other way. None of them is forced by JSON or
by Delphi, so they are worth knowing before they surprise you. Each has a test named after
it in [`TestGotchas.pas`](../dunitx/TestGotchas.pas).

- **`{}` builds an instance.** An empty object is a value, so
  `{"Inner":{}}` gives you a `TInner` with default fields rather than `nil` - the same way
  `[]` has always built an empty `TList`.
- **`null` is not a shorthand for empty.** It is a type mismatch for numbers, strings,
  dates and records: *the document said nothing* and *the value is zero* are different
  claims. It is accepted only where "nothing" is representable — a class or container
  (which becomes `nil`), a typed pointer (likewise), a `Variant` (`varNull`) and a set (the
  empty set).
- **`null` into a class *frees* the instance.** The destination owns what it points at and
  Delphi has no GC, so setting the reference to `nil` without freeing would orphan the
  object beyond the caller's reach. If you hold a second reference to that object
  somewhere else, it is left dangling.
- **`null` into a typed pointer sets it to `nil` and frees nothing.** The opposite of a
  class, and for a reason: the library cannot tell whether the target came from its own
  allocation, from `New` or from a local variable, so it cannot know whether freeing it is
  right. If the pointer held the only reference to memory you allocated, free it before
  decoding. In exchange, a `nil` pointer round-trips - it is written as `null`.
- **Encoding goes by the declared type.** A member declared as `TAnimal` that holds a
  `TDog` is written as a `TAnimal`: the members only `TDog` has are left out. Decoding can
  only build the declared type, so writing the instance's own class would produce documents
  that do not read back. Declare the member as the class you want written.
- **A class is built with a parameterless constructor.** Decoding into `nil` builds the
  instance through the nearest `Create` without parameters up its ancestry - `TObject`'s,
  at the bottom. A class that only has a constructor with parameters never runs it, so
  whatever that constructor sets up is missing: a list it would have created stays `nil`.
  Give the class a parameterless `Create`, or decode into an instance you constructed.
- **A member nobody would put in a document is skipped, not refused.** An interface
  (anonymous methods - `TProc`, `TFunc<T>` - included), a method or procedure pointer, a
  class reference or an untyped `Pointer` does not appear in the output and is ignored on
  the way in — the choice JavaScript's `JSON.stringify` makes for functions. It applies to
  the *type*, so a round trip through such a member loses it silently. Anything that only
  *contains* one is refused with `JSONUnsupportedType`, empty or `nil`: a
  `TArray<IInterface>`, a `TList<TNotifyEvent>`, a `^IInterface`. To leave out a member
  that would be refused, mark it `[JSON('-')]`.
- **A repeated key: the last one wins.** `{"A":1,"A":2}` decodes to `2`. JSON does not say
  what a duplicate means, so this is our choice.
- **A key finds its member whatever the case of a to z.** `{"firstname":"Ada"}` fills
  `FirstName`, as it would match a Delphi identifier. Only the ASCII letters fold:
  `"köln"` finds a member named `Köln`, `"KÖLN"` does not. When two members differ only in
  case - possible through `[JSON]` names - the first one declared takes the key, even if a
  later one matches it exactly. A dynamic document matches keys exactly instead; see
  [Dynamic documents](dynamic-documents.md).
- **Decoding an object *merges*.** A member the document does not name keeps whatever the
  destination already held. Decoding into a reused variable can therefore leave values
  behind from the document before it.
- **Decoding an aggregate *replaces*.** A dynamic array is replaced the way an assignment
  replaces it - another variable that shared the old array keeps the old array - and `TList`,
  `TStrings`, `TDictionary` and sets are cleared first - before the document's shape is
  even checked, so a refused document leaves them empty. An aggregate is one whole value,
  not a set of named parts.
- **A static array must match the document exactly.** Its length is part of its type, so
  `[1,2]` and `[1,2,3,4,5]` are both a `JSONTypeMismatch` for an `array[0..3]`, and so is
  `[]`. Use a dynamic array (`TArray<T>`) when the length varies.
- **A number outside the destination's range is refused, not truncated.** `300` into a
  `byte` is a `JSONTypeMismatch`, not `44`. The range comes from the type itself, so a
  subrange gets its own declared bounds.
- **A real where a whole number is wanted is refused.** `1.9` into an `integer` is a
  `JSONTypeMismatch`, and so are `2.0` and `1e2`: the form of the number decides, not its
  value, as in Go. A producer that writes whole numbers from a float - Python's `3.0` -
  needs a `double` on this side.
- **A descendant of `TInterfacedObject` encodes `RefCount`.** It is a public property of
  that class, so it goes out like any other. Redeclare it with the skip attribute to hide
  it - a member a descendant redeclares hides the ancestor's, as it does in Delphi:

      TMyDto = class(TInterfacedObject, IMyDto)
      public
        Name: string;
        [JSON('-')] property RefCount;
      end;

- **A `TDateTime` is taken to be UTC.** `Now` is local time, and by default it goes out as
  if it were UTC: 14:00 in Berlin in summer is written `14:00Z`, two hours off. Set
  `DateTimeIsUTC` to `false` if your values are local time - see
  [Configuration](configuration.md#dates-and-times).
- **A `TStrings` is written as an object only if *every* entry has a name.** One entry
  without an `=` makes the whole list an array, so nothing is ever dropped for want of a
  key. It is still a guess — a plain string containing `=` is indistinguishable from a
  pair — and `DetectKeyValuePairs` turns the guess off. Decoding needs no guess: `{` is an
  object and `[` is an array, whatever the setting says.
- **A `TStrings` cannot hold every key.** An entry is `name=value`, split at the first
  `=`, so a key that contains `=` or is empty has no entry that represents it. Decoding
  takes the key anyway rather than refusing the document, and it reads back as something
  else: `{"a=b":"1"}` re-encodes as `{"a":"b=1"}`, and `{"":"1"}` as `["=1"]`. Decode into
  a `TDictionary<string,string>` when the keys are not yours to choose.
- **A `TStrings` takes any scalar as text.** It is the loose, untyped destination: `1`
  goes in as `"1"` and `true` as `"true"`, in the array form and as an object's values
  alike. `null` goes in as the empty string, because the text `"null"` would read back as
  a value the document never had. An array or an object as an element is still a
  `JSONTypeMismatch` - it has no text to go in as.
- **A `NaN` or an infinity cannot be written.** They are legal doubles and JSON has no
  spelling for either, so a member holding one makes `Marshal` answer `JSONTypeMismatch`
  and name the member in `TJSONErrorInfo`. The alternatives were an unquoted `NAN` - which
  no parser accepts, this library's included - and `null`, which is what JavaScript's
  `JSON.stringify` does. Refusing is the only one of the three that cannot lose data
  silently.
- **On Win64 a long number can come back as its neighbour.** A `single` or `double` is
  written with the shortest digits that read back as exactly it, so writing loses nothing:
  `0.1` stays `0.1`, and `1/3` is `0.3333333333333333`. Reading is exact for what ordinary
  data holds - up to 15 significant digits, most of 16, a decimal exponent within 22 either
  way: coordinates, prices, measurements. Beyond that the number goes to the RTL's
  `TryStrToFloat`. On Win32 that is nearly always exact; on Win64, where `extended` is a
  `double`, it reads about a third of 17-digit numbers one bit off, reporting `JSONOK` -
  text from JavaScript, Go or Python, and this library's own: `1.2345678901234567` can come
  back as its neighbour. On Win32, about one in 14,000 numbers inside that range is off by
  one bit, a rounding the RTL always made the same way. A correctly rounded reader for the
  rest was considered and not taken; it would add a fair share to a single unit. An
  80-bit `extended` on Win32 and a `Comp` are still written with `FloatToStr`'s 15 digits.
- **A system `TColor` cannot be written.** `clBtnFace` and friends are an index with the
  high byte set rather than an RGB triple, so there is no `"#rrggbb"` for them and they are
  refused instead of written as a different colour.
- **A lone UTF-16 surrogate becomes U+FFFD.** A `string` can hold half of a surrogate pair,
  which is not a character and has no UTF-8 form. It is written as the replacement
  character with `JSONOK`, as Go does, and an escaped one in a document (`\ud800`) is read
  the same way - so a round trip replaces it. Refusing would fail whole documents over
  text pasted from a broken source; an escape of it would be valid JSON whose meaning the
  RFC leaves open.

## Limitations

### 1. Static array members need to have a type (RTTI limitation):
Delphi emits no type info for an inline static array, so a member of one is refused with
`JSONUnsupportedType` - on encode always, on decode when the document names it. Declare the
type, or mark the member `[JSON('-')]`.

    // inline static arrays are refused
    type WontWork = record
        Items: array[0..9] of Integer; 
    end;
    
    // if static arrays are types, they will...
    type TenItems = array[0..9] of Integer;
    type ThisWorks = record
        Items: TenItems;
    end;

### 2. Sets need an enumeration as their base type, enumerations need default values
A `set of SomeEnum` encodes as an array of member names. Delphi emits no type info for a
set over a *subrange* (`set of 8..15`, `set of someValue..someOtherValue`) or for an
enumeration with explicit values (`(a = 1, b = 5)`), so a field of either type is refused
like an inline static array, and so is a set over such an enumeration. A *property* of
either type is not even seen: Delphi leaves it out of RTTI, so it is skipped without a
word.

### 3. A variant document is read-only in its nested parts
`doc.inner.x := 2` compiles, runs, raises nothing - and is discarded. See
[Dynamic documents](dynamic-documents.md#assignment-copies-the-whole-document) for why, and for the read-modify-write
idiom that does work.

### 4. Properties on records are not supported
Would like to have that too, but `System.RTTI` does not seem to have code for that.

### 5. A document is handled whole, in memory
There is no stream interface in either direction. `Unmarshal` reads from a `PAnsiChar` and
a length, a `UTF8String` or a `UnicodeString`, and `Marshal` builds the complete document
as a `UTF8String` before handing it back. So the whole document and the value it describes
are in memory at the same time, and the `UnicodeString` forms add a UTF-8 copy on top. To
read a file, load it first and pass the bytes; to write one, save the string you get back.
That suits configuration, API payloads and records of a few megabytes - it is not built for
a multi-gigabyte log you would want to process one element at a time.
