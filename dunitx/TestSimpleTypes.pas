unit TestSimpleTypes;

// Scalars at the top level and through typed pointers, the convenience
// overloads, and what happens to the value of a key no member takes.

interface

uses
  DUnitX.TestFramework,
  encoding.json;

type
  [TestFixture]
  TSimpleTypesTest = class
  public
    [Test] procedure TestScalarsRoundTrip;
    [Test] procedure TestFloatsAreWrittenShortest;
    [Test] procedure TestThroughPointers;
    [Test] procedure TestEscapedStringRoundTrips;
    [Test] procedure TestMalformedNumberInSkippedFieldIsRejected;
    [Test] procedure TestUnknownAggregateFieldIsSkipped;
    [Test] procedure TestMalformedAggregateInSkippedFieldIsRejected;
    [Test] procedure TestMarshalAsAnExpression;
  end;

implementation

uses
  System.SysUtils,
  TestHelpers;

type
  TExpressionPerson = record
    Name: string;
    Age: integer;
  end;

  TUnencodable = record
    Handlers: array of procedure of object;
  end;

// the one pair that raises - an empty string would look like a document
procedure TSimpleTypesTest.TestMarshalAsAnExpression;
var
  somePerson: TExpressionPerson;
  cannotEncode: TUnencodable;
  asCode: string;
  raised: boolean;
begin
  somePerson.Name:= 'John';
  somePerson.Age:= 42;

  Assert.AreEqual('{"Name":"John","Age":42}',JSON.Marshal(somePerson));
  Assert.AreEqual('{'#10'  "Name": "John",'#10'  "Age": 42'#10'}',
    JSON.MarshalIndent(somePerson,'  '));

  // the result-code overloads still resolve, and still do not raise
  Assert.AreEqual(JSONOK,JSON.Marshal(somePerson,asCode));
  Assert.AreEqual('{"Name":"John","Age":42}',asCode);

  SetLength(cannotEncode.Handlers,1);
  raised:= false;
  try
    JSON.Marshal(cannotEncode);
  except
    on e: EJSONError do begin
      raised:= true;
      Assert.AreEqual(JSONUnsupportedType,e.Info.Code,'the code travels on the exception');
      Assert.IsTrue(Pos('Handlers',e.Message) > 0,'and the member is named: '+e.Message);
    end;
  end;
  Assert.IsTrue(raised,'a document that cannot be produced has to raise');
end;


procedure TSimpleTypesTest.TestScalarsRoundTrip;
begin
  Check.RoundTrips<string>('some string','"some string"','string');
  Check.RoundTrips<integer>(42,'42','integer');
  Check.RoundTrips<double>(3.14159,'3.14159','double');
  Check.RoundTrips<boolean>(true,'true','true');
  Check.RoundTrips<boolean>(false,'false','false');
  Check.RoundTrips<TObject>(nil,'null','a nil object');
end;

// the shortest digits that read back as exactly the float, in FloatToStr's
// layout: fixed from 0.0001 up to 15 integral digits, scientific beyond
procedure TSimpleTypesTest.TestFloatsAreWrittenShortest;
var
  zero: double;
begin
  Check.RoundTrips<double>(0.1,'0.1','0.1');
  Check.RoundTrips<double>(1/3,'0.3333333333333333','a third, 16 digits');
  Check.RoundTrips<double>(100,'100','a whole number has no fraction');
  Check.RoundTrips<double>(0.0001,'0.0001','fixed down to 0.0001');
  Check.RoundTrips<double>(0.00001,'1E-5','...scientific below');
  Check.RoundTrips<double>(123456789012345,'123456789012345','fixed up to 15 integral digits');
  Check.RoundTrips<double>(1E15,'1E15','...scientific beyond');
  Check.RoundTrips<double>(5E-324,'5E-324','the smallest subnormal');

  // a single gets the digits of a single, not of the double it widens to
  Check.RoundTrips<single>(0.1,'0.1','a single');

  // the sign of a zero survives
  zero:= 0;
  zero:= -zero;
  Check.RoundTrips<double>(zero,'-0','minus zero');
end;

// a typed pointer is followed on the way out and decoded through on the way
// in; a nil one gets its target allocated, the way New would
procedure TSimpleTypesTest.TestThroughPointers;
var
  s: string;
  i: integer;
  d: double;
  b: boolean;
  pStr: PString;
  pInt: PInteger;
  pDbl: PDouble;
  pBool: PBoolean;
begin
  s:= 'some string'; pStr:= @s;
  i:= 42;            pInt:= @i;
  d:= 3.14159;       pDbl:= @d;
  b:= true;          pBool:= @b;
  Check.Encodes<PString>(pStr,'"some string"','string');
  Check.Encodes<PInteger>(pInt,'42','integer');
  Check.Encodes<PDouble>(pDbl,'3.14159','double');
  Check.Encodes<PBoolean>(pBool,'true','boolean');

  Assert.AreEqual(JSONOK,JSON.Unmarshal('"other"',pStr));
  Assert.AreEqual('other',s);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('7',pInt));
  Assert.AreEqual(7,i);
  Assert.AreEqual(JSONOK,JSON.Unmarshal('2.5',pDbl));
  Assert.IsTrue(d = 2.5,'double');
  Assert.AreEqual(JSONOK,JSON.Unmarshal('false',pBool));
  Assert.IsFalse(b,'boolean');

  pInt:= nil;
  Assert.AreEqual(JSONOK,JSON.Unmarshal('42',pInt));
  Assert.IsNotNull(pInt);
  Assert.AreEqual(42,pInt^);
  Dispose(pInt);
end;

procedure TSimpleTypesTest.TestEscapedStringRoundTrips;
begin
  Check.RoundTrips<string>('Österreich,Übertragung,Gießen'#13#10'Etwas steht in "Anführungszeichen"',
    '"Österreich,Übertragung,Gießen\r\nEtwas steht in \"Anführungszeichen\""','umlauts, a line break, quotes');
  Check.RoundTrips<string>(#13#10,'"\r\n"','nothing but a line break');
end;

type TRecordWithOneField = record
  a: integer;
end;

// a skipped value is never converted, so the reader itself must refuse "1e+"
procedure TSimpleTypesTest.TestMalformedNumberInSkippedFieldIsRejected;
var
  someRecord: TRecordWithOneField;
  someJSON: UTF8String;
begin
  someJSON:= '{"a":1,"b":1e+}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'1e+');

  someJSON:= '{"a":1,"b":1e-}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'1e-');

  // ...while well-formed exponents in a skipped field stay valid
  someJSON:= '{"a":1,"b":1e+5}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'1e+5');

  someJSON:= '{"a":1,"b":-0.25e-3}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'-0.25e-3');
end;

// an unknown member's aggregate is consumed whole, not just its first token
procedure TSimpleTypesTest.TestUnknownAggregateFieldIsSkipped;
var
  someRecord: TRecordWithOneField;
  someJSON: UTF8String;
begin
  someRecord.a:= 0;
  someJSON:= '{"b":[1,2,3],"a":1}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'array');
  Assert.AreEqual(1,someRecord.a,'array');

  someRecord.a:= 0;
  someJSON:= '{"b":{"x":1},"a":2}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'object');
  Assert.AreEqual(2,someRecord.a,'object');

  someRecord.a:= 0;
  someJSON:= '{"b":{"x":[1,{"y":[[],{}]},null],"z":{}},"a":3}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'nested');
  Assert.AreEqual(3,someRecord.a,'nested');

  someRecord.a:= 0;
  someJSON:= '{"b":[],"c":{},"a":4}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'empty aggregates');
  Assert.AreEqual(4,someRecord.a,'empty aggregates');

  // a known name nested inside a skipped value belongs to that value
  someRecord.a:= 0;
  someJSON:= '{"b":{"a":99},"a":5}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'shadowed name');
  Assert.AreEqual(5,someRecord.a,'shadowed name');

  // brackets inside a skipped string are data, not structure
  someRecord.a:= 0;
  someJSON:= '{"b":"}]}]","a":6}';
  Assert.AreEqual(JSONOK,JSON.Unmarshal(someJSON,someRecord),'brackets in string');
  Assert.AreEqual(6,someRecord.a,'brackets in string');
end;

// skipping is not a hole in the parser: what gets thrown away still has to be
// well-formed, and the depth-limit still applies to it.
procedure TSimpleTypesTest.TestMalformedAggregateInSkippedFieldIsRejected;
var
  someRecord: TRecordWithOneField;
  someJSON: UTF8String;
begin
  someJSON:= '{"a":1,"b":[1,,2]}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'hole in array');

  someJSON:= '{"a":1,"b":{"x":}}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'missing value');

  someJSON:= '{"a":1,"b":{x:1}}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'unquoted key');

  someJSON:= '{"a":1,"b":[1,2}';
  Assert.AreEqual(JSONSyntax,JSON.Unmarshal(someJSON,someRecord),'unterminated array');

  someJSON:= '{"b":'+UTF8String(StringOfChar('[',100)+'1'+StringOfChar(']',100))+',"a":1}';
  Assert.AreEqual(JSONMaxDepthReached,JSON.Unmarshal(someJSON,someRecord),'too deep');
end;

initialization
  TDUnitX.RegisterTestFixture(TSimpleTypesTest);

end.
