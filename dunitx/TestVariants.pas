unit TestVariants;

// What a Variant can carry each way. In, the notation picks the subtype - a
// fraction or an exponent makes a Double, anything else an Int64. Out, a subtype
// without a JSON form is refused, never written as something plausible.

interface

uses
  DUnitX.TestFramework,
  Variants,
  encoding.json;

type
  [TestFixture]
  TVariantsTest = class
  public
    [Test] procedure TestVariantEncode;
    [Test] procedure TestVariantDecode;
    [Test] procedure TestOLEVariantEncode;

    [Test] procedure TestNumberNotationDecidesTheSubtype;
    [Test] procedure TestEncodeRejectsSubtypesWithNoJSONForm;
  end;

implementation

uses
  SysUtils;

// TestVariantEncode tests encoding of variants containing those subtypes
// string, integer, float, bool, null
procedure TVariantsTest.TestVariantEncode;
var
  value: Variant;
  gotJSON: string;
  gotResult: TJSONResult;
begin
  value:= 'a string';
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('"a string"',gotJSON);

  value:= 42;
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('42',gotJSON);

  value:= 3.14159;
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('3.14159',gotJSON);

  value:= true;
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('true',gotJSON);

  value:= Variants.Null;
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('null',gotJSON);
end;


// TestVariantDecode tests decoding of simple values into a variant
// "Simple" here means: string, integer, float, bool, null

procedure TVariantsTest.TestVariantDecode;
var
  someJSON: string;
  gotValue: Variant;
  gotResult: TJSONResult;
begin
  someJSON:= '"a string"';
  gotResult:= JSON.Unmarshal(someJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(Variant('a string'),gotValue);

  someJSON:= '42';
  gotResult:= JSON.Unmarshal(someJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(Variant(42),gotValue);

  someJSON:= '3.14159';
  gotResult:= JSON.Unmarshal(someJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(Variant(3.14159),gotValue);

  someJSON:= 'true';
  gotResult:= JSON.Unmarshal(someJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(Variant(true),gotValue);

  someJSON:= 'null';
  gotResult:= JSON.Unmarshal(someJSON,gotValue);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual(Variants.Null,gotValue);
end;


procedure TVariantsTest.TestOLEVariantEncode;
var
  value: OLEVariant;
  gotJSON: string;
  gotResult: TJSONResult;
begin
  value:= 'a string';
  gotResult:= JSON.Marshal(value,gotJSON);
  Assert.AreEqual(JSONOK,gotResult);
  Assert.AreEqual('"a string"',gotJSON);

end;


// the notation decides, not the value: 1e2 is a real
procedure TVariantsTest.TestNumberNotationDecidesTheSubtype;
var
  got: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('42'),got),'a plain integer');
  Assert.AreEqual(integer(varInt64),integer(VarType(got)),'...stays an integer');
  Assert.IsTrue(got = 42,'42');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('1.5'),got),'a fraction');
  Assert.AreEqual(integer(varDouble),integer(VarType(got)),'...is a real');
  Assert.IsTrue(got = 1.5,'1.5');

  // an exponent makes a real, with or without a dot
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('1e2'),got),'an exponent and no dot');
  Assert.AreEqual(integer(varDouble),integer(VarType(got)),'an exponent makes it a real');
  Assert.IsTrue(got = 100,'1e2 is 100');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('-3E-2'),got),'a capital E and a sign');
  Assert.AreEqual(integer(varDouble),integer(VarType(got)),'...also a real');
  Assert.IsTrue(Abs(double(got) - (-0.03)) < 1e-12,'-3E-2 is -0.03');

  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('1.5e3'),got),'both at once');
  Assert.AreEqual(integer(varDouble),integer(VarType(got)),'...still a real');
  Assert.IsTrue(got = 1500,'1.5e3 is 1500');

  // a whole number Int64 cannot hold becomes a real, as in Go, rather than
  // failing the whole document
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('9223372036854775807'),got),'High(Int64)');
  Assert.AreEqual(integer(varInt64),integer(VarType(got)),'...still fits');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('18446744073709551615'),got),'High(UInt64)');
  Assert.AreEqual(integer(varDouble),integer(VarType(got)),'...past Int64, a real');
  // 2^64: the nearest double, and exact in an 80-bit extended as well
  Assert.IsTrue(double(got) = 18446744073709551616.0,'...with the nearest value');
  Assert.AreEqual(JSONOK,JSON.Unmarshal(UTF8String('[1,-99999999999999999999]'),got),'inside an array');
  Assert.AreEqual(integer(varDouble),integer(VarType(got[1])),'...the big one a real');
  Assert.IsTrue(double(got[1]) = -1e20,'...-1e20');
end;

// refused, not written as null with JSONOK
procedure TVariantsTest.TestEncodeRejectsSubtypesWithNoJSONForm;
var
  value: Variant;
  gotJSON: string;
begin
  // Null and Unassigned both mean "nothing here", and null is how JSON says
  // that - these two keep their meaning
  value:= Variants.Null;
  Assert.AreEqual(JSONOK,JSON.Marshal(value,gotJSON),'Null');
  Assert.AreEqual('null',gotJSON,'Null is a JSON value');

  value:= Unassigned;
  Assert.AreEqual(JSONOK,JSON.Marshal(value,gotJSON),'Unassigned');
  Assert.AreEqual('null',gotJSON,'Unassigned has no better JSON form');

  // a variant array has a JSON form; the round-trip detail is in TestVarDict
  value:= VarArrayCreate([0,1],varVariant);
  value[0]:= 1;
  value[1]:= 'two';
  Assert.AreEqual(JSONOK,JSON.Marshal(value,gotJSON),'a variant array');
  Assert.AreEqual('[1,"two"]',gotJSON);

  // the empty one too: the type decides, not the contents
  value:= VarArrayCreate([0,-1],varVariant);
  Assert.AreEqual(JSONOK,JSON.Marshal(value,gotJSON),'an empty variant array');
  Assert.AreEqual('[]',gotJSON);

  // what is left with no JSON form: an interface reference, of either kind
  value:= Unassigned;
  TVarData(value).VType:= varUnknown;
  TVarData(value).VUnknown:= nil;
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(value,gotJSON),'an interface');

  value:= Unassigned;
  TVarData(value).VType:= varDispatch;
  TVarData(value).VDispatch:= nil;
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(value,gotJSON),'a dispatch interface');

  // more than one dimension has no JSON form - only an array of arrays does
  value:= VarArrayCreate([0,1,0,1],varVariant);
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(value,gotJSON),'a two-dimensional array');

  // a date the RTL cannot format is the field's refusal too, by the same route
  value:= VarFromDateTime(MaxDateTime+1);
  Assert.AreEqual(JSONTypeMismatch,JSON.Marshal(value,gotJSON),'a date past the year 9999');
end;

initialization
  TDUnitX.RegisterTestFixture(TVariantsTest);

end.
