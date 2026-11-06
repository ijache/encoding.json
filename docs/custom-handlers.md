# Custom parsers and formatters

How to take over encoding or decoding for a type, replace a built-in, or build on one. The
rest of the documentation is in the [README](../README.md).

A handler is a plain function. It gets the destination address and writes to it, or reads
from it — there is no intermediate DOM:

    function FormatMoney(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
    begin
      w.WriteString(Format('%d.%.2d',[PMoney(data).Cents div 100,
                                      PMoney(data).Cents mod 100]));
      result := JSONOK;
    end;

    JSON.RegisterFormatter<TMoney>(@FormatMoney);

A formatter has `BeginObject`/`EndObject`, `BeginArray`/`EndArray`, `WriteKey`,
`WriteInteger`, `WriteBoolean`, `WriteNull`, `WriteString` - a JSON string, quoted and
escaped - and `WriteRaw`, which writes JSON text as it is: nothing checks it, so it has to
be valid JSON already, a number written by `FloatToStr` say. A parser has
`PeekNextToken`/`ConsumeToken`, `ReadValue`, `SkipValue`, `LastValue`/`LastValueRaw` and
`ShapeError`.

A handler returns a result code like every entry point does; see
[Error handling](errors.md).

## Registering

`RegisterParser` and `RegisterFormatter` each take a qualified type name, a `PTypeInfo`, or
a `<T>`. The string form is the one that can name a *base class* or an open generic — the
built-ins use it, e.g. `'System.Generics.Collections.TList'` covers every `TList<T>`:

    JSON.RegisterFormatter('System.TDateTime', @MyDateFormat);   // override a built-in
    JSON.RegisterFormatter('System.TDateTime', nil);             // remove one

A type declared in an implementation section or in the program file has no qualified name,
so it can only be registered through `<T>` or its `PTypeInfo`.

Registering a name that is already known replaces it, which is how a built-in gets
overridden. Like `Configure`, these are **not thread-safe** and are meant for startup: each
registration rebuilds the type cache, because a member's handler is resolved once
when its type is first seen.

## Delegating to another handler

`GetFormatterForTypeInfo` and `GetParserForTypeInfo` return the handler any type would get -
a built-in or a registered one - so a handler can do its own part and pass the rest on. A
nullable integer decides about `null` itself and leaves the number, range check included,
to the built-in for `integer`:

    type
      TNullableInt = record
        HasValue: boolean;
        Value: integer;
      end;
      PNullableInt = ^TNullableInt;

    function FormatNullableInt(j: TJSONCodec; w: PJSONWriter; ti: PTypeInfo; data: Pointer): TJSONResult;
    var
      f: TJSONFormatter;
    begin
      if not PNullableInt(data).HasValue then begin
        w.WriteNull;
        exit(JSONOK);
      end;
      f:= j.GetFormatterForTypeInfo(TypeInfo(integer));
      result:= f(j,w,TypeInfo(integer),@PNullableInt(data).Value);
    end;

    function ParseNullableInt(j: TJSONCodec; r: PJSONReader; ti: PTypeInfo; data: Pointer): TJSONResult;
    var
      p: TJSONParser;
    begin
      if r.PeekNextToken = 'n' then begin
        result:= r.ReadValue;    // the null - or the error for whatever else began with 'n'
        if result = JSONOK then PNullableInt(data).HasValue:= false;
        exit;
      end;
      p:= j.GetParserForTypeInfo(TypeInfo(integer));
      result:= p(j,r,TypeInfo(integer),@PNullableInt(data).Value);
      PNullableInt(data).HasValue:= (result = JSONOK);
    end;

    JSON.RegisterFormatter<TNullableInt>(@FormatNullableInt);
    JSON.RegisterParser<TNullableInt>(@ParseNullableInt);

A record holding a `TNullableInt` member now encodes it as `42` or `null`, and `"x"` or
`3000000000` for it is refused exactly as for a plain `integer`.

Both functions answer from the registry, so asking for the type your own handler is
registered for returns your own handler: once a built-in is replaced, a handler cannot reach
it any more. They return `nil` for a type nothing can handle.
[`TestRegister.pas`](../dunitx/TestRegister.pas) runs this example.
