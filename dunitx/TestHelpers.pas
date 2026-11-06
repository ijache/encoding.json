unit TestHelpers;

// RoundTrips compares through the text: encode to "want", decode, encode to "want"
// again - no equality operator needed, and a dropped member shows. Not for typed
// pointers: it could not release an allocated target.

interface

uses
  DUnitX.TestFramework,
  System.TypInfo,
  encoding.json;

type
  Check = record
    class procedure Encodes<T>(const v: T; const want: string; const why: string = ''); static;
    class procedure RoundTrips<T>(const v: T; const want: string; const why: string = ''); static;
  end;

implementation

class procedure Check.Encodes<T>(const v: T; const want: string; const why: string);
var
  s: string;
begin
  Assert.AreEqual(JSONOK,JSON.Marshal<T>(v,s),why);
  Assert.AreEqual(want,s,why);
end;

class procedure Check.RoundTrips<T>(const v: T; const want: string; const why: string);
var
  got: T;
  s: string;
begin
  Assert.IsTrue(PTypeInfo(TypeInfo(T)).Kind <> tkPointer,'RoundTrips cannot release a pointer target');
  Encodes<T>(v,want,why);

  got:= Default(T);
  Assert.AreEqual(JSONOK,JSON.Unmarshal<T>(want,got),why+' - decode');
  Assert.AreEqual(JSONOK,JSON.Marshal<T>(got,s),why+' - encode again');
  Assert.AreEqual(want,s,why+' - round trip');

  if PTypeInfo(TypeInfo(T)).Kind = tkClass then TObject(PPointer(@got)^).Free;
end;

end.
