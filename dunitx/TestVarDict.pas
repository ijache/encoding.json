unit TestVarDict;

// Dynamic documents: TVarDict as a variant type (lifetime, deep copy, late
// binding) and the JSON either side. A wrong Clear would read back fine and never
// free - the leak monitor catches that. Keys can be compared as text: the encoder
// sorts them.

interface

uses
  DUnitX.TestFramework;

type
  TVariantHolder = record
    Doc: Variant;
  end;

  [TestFixture]
  TVarDictTest = class
  public
    // the variant type itself
    [Test] procedure TestVarDictIsADict;
    [Test] procedure TestScalarsAreNotDicts;
    [Test] procedure TestSetAndGetAProperty;
    [Test] procedure TestLookupIsCaseSensitive;
    [Test] procedure TestKeysDifferingOnlyInCaseBothSurvive;
    [Test] procedure TestOriginalCasingIsKept;
    [Test] procedure TestMissingKeyIsUnassigned;
    [Test] procedure TestNullAndMissingAreDifferent;
    [Test] procedure TestOverwritingAKeyKeepsOneEntry;
    [Test] procedure TestNesting;
    [Test] procedure TestAssignmentDeepCopies;
    [Test] procedure TestNestedAssignmentDeepCopies;
    [Test] procedure TestSettingAMemberCopiesTheValueIn;
    [Test] procedure TestNestedWriteThroughAPathIsLost;

    // decoding
    [Test] procedure TestDecodeObject;
    [Test] procedure TestDecodeArray;
    [Test] procedure TestDecodeScalarsStillWork;
    [Test] procedure TestDecodeNestedArray;
    [Test] procedure TestDecodeNestedObject;
    [Test] procedure TestDecodeEmptyObjectAndArray;
    [Test] procedure TestDecodeNullInsideADocument;
    [Test] procedure TestDecodeRespectsMaxDepth;
    [Test] procedure TestDecodeIntoARecordMember;
    [Test] procedure TestArrayOfVariantNowNests;

    // encoding
    [Test] procedure TestEncodeArray;
    [Test] procedure TestBuildADocumentFromNothing;
    [Test] procedure TestRoundTrip;
    [Test] procedure TestEncodeSortsKeys;
    [Test] procedure TestSortOrderMatchesRecords;
    [Test] procedure TestEmptyDictIsNotOmitted;
    [Test] procedure TestEncodeRejectsMultiDimensionalArrays;
  end;

implementation

uses
  System.SysUtils,
  System.Variants,
  encoding.json;

procedure TVarDictTest.TestVarDictIsADict;
var
  v: Variant;
begin
  v:= VarDictCreate;
  Assert.IsTrue(VarIsDict(v));
end;

procedure TVarDictTest.TestScalarsAreNotDicts;
var
  v: Variant;
begin
  v:= 42;                    Assert.IsFalse(VarIsDict(v),'integer');
  v:= 'text';                Assert.IsFalse(VarIsDict(v),'string');
  v:= 1.5;                   Assert.IsFalse(VarIsDict(v),'float');
  v:= true;                  Assert.IsFalse(VarIsDict(v),'boolean');
  v:= System.Variants.Null;  Assert.IsFalse(VarIsDict(v),'null');
  v:= Unassigned;            Assert.IsFalse(VarIsDict(v),'unassigned');
  v:= VarArrayCreate([0,1],varVariant);
  Assert.IsFalse(VarIsDict(v),'array');
end;

procedure TVarDictTest.TestSetAndGetAProperty;
var
  v: Variant;
begin
  v:= VarDictCreate;
  v.name:= 'Ada';
  v.age:= 36;

  Assert.AreEqual('Ada',string(v.name));
  Assert.AreEqual(36,integer(v.age));
end;

// no declared members to match against: the key is the data
procedure TVarDictTest.TestLookupIsCaseSensitive;
var
  v: Variant;
begin
  v:= VarDictCreate;
  v.Name:= 'Ada';

  Assert.AreEqual('Ada',string(v.Name),'as written');
  Assert.IsTrue(VarIsEmpty(v.name),'lower is a different key');
  Assert.IsTrue(VarIsEmpty(v.NAME),'upper is a different key');
end;

// {"a":1,"A":2} is two members, and stays two
procedure TVarDictTest.TestKeysDifferingOnlyInCaseBothSurvive;
var
  v: Variant;
  s: string;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"a":1,"A":2}',v));
  Assert.AreEqual(1,integer(v.a),'lower');
  Assert.AreEqual(2,integer(v.A),'upper');

  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  // ordinal, so 'A' (0x41) comes before 'a' (0x61)
  Assert.AreEqual('{"A":2,"a":1}',s,false);
end;

// TInvokeableVariantType.FixupIdent uppercases the identifier by default,
// which would store the key as FIRSTNAME and encode it back out that way.
procedure TVarDictTest.TestOriginalCasingIsKept;
var
  v: Variant;
  s: string;
begin
  v:= VarDictCreate;
  v.firstName:= 'Ada';

  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('{"firstName":"Ada"}',s,false);
end;

procedure TVarDictTest.TestMissingKeyIsUnassigned;
var
  v: Variant;
begin
  v:= VarDictCreate;
  v.present:= 1;

  Assert.IsTrue(VarIsEmpty(v.absent),'a key that was never set');
  Assert.IsFalse(VarIsEmpty(v.present),'one that was');
end;

// settled point 3 of the variant plan: absent and explicitly-null have to stay
// tellable apart, or a document cannot be edited without losing that
procedure TVarDictTest.TestNullAndMissingAreDifferent;
var
  v: Variant;
begin
  v:= VarDictCreate;
  v.explicit:= System.Variants.Null;

  Assert.IsTrue(VarIsNull(v.explicit),'null is null');
  Assert.IsFalse(VarIsEmpty(v.explicit),'null is not empty');

  Assert.IsTrue(VarIsEmpty(v.missing),'missing is empty');
  Assert.IsFalse(VarIsNull(v.missing),'missing is not null');
end;

procedure TVarDictTest.TestOverwritingAKeyKeepsOneEntry;
var
  v: Variant;
  s: string;
begin
  v:= VarDictCreate;
  v.k:= 1;
  v.k:= 2;   // same key, written twice

  Assert.AreEqual(2,integer(v.k));
  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('{"k":2}',s,false);
end;

procedure TVarDictTest.TestNesting;
var
  outer,inner: Variant;
begin
  inner:= VarDictCreate;
  inner.deep:= 'value';

  outer:= VarDictCreate;
  outer.inner:= inner;

  Assert.IsTrue(VarIsDict(outer.inner),'nested dict survives');
  Assert.AreEqual('value',string(outer.inner.deep));
end;

// settled point 1: v2 := v1 yields an independent tree
procedure TVarDictTest.TestAssignmentDeepCopies;
var
  a,b: Variant;
begin
  a:= VarDictCreate;
  a.x:= 1;

  b:= a;
  b.x:= 2;

  Assert.AreEqual(1,integer(a.x),'the original is untouched');
  Assert.AreEqual(2,integer(b.x),'the copy changed');
end;

procedure TVarDictTest.TestNestedAssignmentDeepCopies;
var
  a,b,inner,t: Variant;
begin
  inner:= VarDictCreate;
  inner.x:= 1;

  a:= VarDictCreate;
  a.inner:= inner;

  b:= a;

  // read-modify-write, because a nested write through a path does not stick.
  // TestNestedWriteThroughAPathIsLost is the one that pins that down.
  t:= b.inner;
  t.x:= 2;
  b.inner:= t;

  // a shallow copy would share the inner store and report 2 here
  Assert.AreEqual(1,integer(a.inner.x),'the original inner is untouched');
  Assert.AreEqual(2,integer(b.inner.x),'the copy changed');
end;

// the value is copied in, so the variable it came from is no longer connected
procedure TVarDictTest.TestSettingAMemberCopiesTheValueIn;
var
  doc,inner: Variant;
begin
  inner:= VarDictCreate;
  inner.x:= 1;

  doc:= VarDictCreate;
  doc.inner:= inner;

  inner.x:= 99;

  Assert.AreEqual(1,integer(doc.inner.x),'the document kept its own copy');
end;

// deep copy has this price: doc.inner is a copy, so writing into it is lost -
// silently, which is why it is pinned
procedure TVarDictTest.TestNestedWriteThroughAPathIsLost;
var
  doc,inner: Variant;
begin
  inner:= VarDictCreate;
  inner.x:= 1;

  doc:= VarDictCreate;
  doc.inner:= inner;

  doc.inner.x:= 2;

  Assert.AreEqual(1,integer(doc.inner.x),'the nested write went to a temporary');
end;


//---------------------------------------------------------------- decoding

procedure TVarDictTest.TestDecodeObject;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"name":"Ada","age":36}',v));
  Assert.IsTrue(VarIsDict(v),'an object decodes to a dictionary');
  Assert.AreEqual('Ada',string(v.name));
  Assert.AreEqual(36,integer(v.age));
end;

procedure TVarDictTest.TestDecodeArray;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,2,3,4]',v));
  Assert.IsTrue(VarIsArray(v),'an array decodes to a variant array');
  Assert.AreEqual(0,VarArrayLowBound(v,1));
  Assert.AreEqual(3,VarArrayHighBound(v,1),'four elements, trimmed');
  Assert.AreEqual(1,integer(v[0]));
  Assert.AreEqual(4,integer(v[3]));
end;

procedure TVarDictTest.TestDecodeScalarsStillWork;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('"text"',v));
  Assert.AreEqual('text',string(v));

  Assert.AreEqual(JSONOK,JSON.Unmarshal('42',v));
  Assert.AreEqual(42,integer(v));

  Assert.AreEqual(JSONOK,JSON.Unmarshal('true',v));
  Assert.IsTrue(boolean(v));

  Assert.AreEqual(JSONOK,JSON.Unmarshal('null',v));
  Assert.IsTrue(VarIsNull(v));
end;

// the case the old TArray<Variant> could not reach: nesting
procedure TVarDictTest.TestDecodeNestedArray;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,[2,3]]',v));
  Assert.IsTrue(VarIsArray(v),'outer');
  Assert.AreEqual(1,integer(v[0]));
  Assert.IsTrue(VarIsArray(v[1]),'inner');
  Assert.AreEqual(2,integer(v[1][0]));
  Assert.AreEqual(3,integer(v[1][1]));
end;

procedure TVarDictTest.TestDecodeNestedObject;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"a":{"b":{"c":"deep"}},"arr":[{"k":1}]}',v));
  Assert.AreEqual('deep',string(v.a.b.c));
  Assert.IsTrue(VarIsArray(v.arr),'array member');
  // element access is a two-step: lift the member into a Variant, then index
  // it as the plain variant array it is
  var arr: Variant := v.arr;
  Assert.AreEqual(1,integer(arr[0].k),'object inside an array');
end;

procedure TVarDictTest.TestDecodeEmptyObjectAndArray;
var
  v: Variant;
  s: string;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{}',v));
  Assert.IsTrue(VarIsDict(v),'empty object is still a dictionary');
  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('{}',s);

  Assert.AreEqual(JSONOK,JSON.Unmarshal('[]',v));
  Assert.IsTrue(VarIsArray(v),'empty array is still an array');
  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('[]',s);
end;

procedure TVarDictTest.TestDecodeNullInsideADocument;
var
  v: Variant;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"present":null}',v));
  Assert.IsTrue(VarIsNull(v.present),'an explicit null');
  Assert.IsTrue(VarIsEmpty(v.absent),'and a key that is not there');
end;

procedure TVarDictTest.TestDecodeRespectsMaxDepth;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  v: Variant;
begin
  cfg:= JSONDefaultConfig;
  cfg.MaxDepth:= 3;
  j:= TJSONCodec.Create(cfg);
  try
    Assert.AreEqual(JSONOK,j.Unmarshal('{"a":{"b":{"c":1}}}',v),'at the limit');
    Assert.AreEqual(JSONMaxDepthReached,j.Unmarshal('{"a":{"b":{"c":{"d":1}}}}',v),'past it');
    Assert.AreEqual(JSONMaxDepthReached,j.Unmarshal('[[[[1]]]]',v),'arrays too');
  finally
    j.Free;
  end;
end;

// a Variant member of a record is the ordinary way to hold one unknown corner
// of an otherwise known document
procedure TVarDictTest.TestDecodeIntoARecordMember;
var
  r: TVariantHolder;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"Doc":{"k":"v"}}',r));
  Assert.IsTrue(VarIsDict(r.Doc));
  Assert.AreEqual('v',string(r.Doc.k));
end;

// TArray<Variant> went through ParseVariant per element all along, so it picks
// up nesting without the array code changing at all
procedure TVarDictTest.TestArrayOfVariantNowNests;
var
  a: TArray<Variant>;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('[1,[2,3],{"k":"v"}]',a));
  Assert.AreEqual(3,integer(Length(a)));
  Assert.AreEqual(1,integer(a[0]));
  Assert.IsTrue(VarIsArray(a[1]),'nested array');
  Assert.IsTrue(VarIsDict(a[2]),'nested object');
  Assert.AreEqual('v',string(a[2].k));
end;


//---------------------------------------------------------------- encoding

procedure TVarDictTest.TestEncodeArray;
var
  v: Variant;
  s: string;
begin
  v:= VarArrayCreate([0,2],varVariant);
  v[0]:= 1;
  v[1]:= 'two';
  v[2]:= true;

  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('[1,"two",true]',s);
end;

// the worked example in docs/dynamic-documents.md, so that it
// is a tested claim rather than a plausible one
procedure TVarDictTest.TestBuildADocumentFromNothing;
var
  doc: Variant;
  s: string;
begin
  doc:= VarDictCreate;
  doc.name:= 'Ada';
  doc.tags:= VarArrayOf([1,2,3]);

  Assert.AreEqual(JSONOK,JSON.Marshal(doc,s));
  Assert.AreEqual('{"name":"Ada","tags":[1,2,3]}',s,false);
end;

// every kind of element after every other kind; [[1],2] once lost its comma
procedure TVarDictTest.TestRoundTrip;
var
  v: Variant;
  s: string;
const
  DOC = '{"active":true,"mixed":[[1],2,{"k":3},[],"s",null,{}],'
      + '"nested":{"x":1},"nothing":null,"nums":[1,2,3],"text":"hi"}';
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal(DOC,v));
  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual(DOC,s,'sorted in, sorted out');
end;

procedure TVarDictTest.TestEncodeSortsKeys;
var
  v: Variant;
  s: string;
begin
  v:= VarDictCreate;
  v.zulu:= 1;
  v.alpha:= 2;
  v.mike:= 3;

  Assert.AreEqual(JSONOK,JSON.Marshal(v,s));
  Assert.AreEqual('{"alpha":2,"mike":3,"zulu":1}',s);
end;

// keys sort with CompareStr, like record members. U+FF01 against U+1F600 is where
// that differs from byte order; built from code units, asserted by position
procedure TVarDictTest.TestSortOrderMatchesRecords;
const
  FULLWIDTH_BANG = #$FF01;
  GRINNING_FACE  = #$D83D#$DE00;
var
  doc: Variant;
  s: string;
begin
  Assert.AreEqual(JSONOK,JSON.Unmarshal('{"'+FULLWIDTH_BANG+'":1,"'+GRINNING_FACE+'":2}',doc));

  Assert.AreEqual(JSONOK,JSON.Marshal(doc,s));
  Assert.IsTrue(Pos(':2',s) < Pos(':1',s),
    'the astral key sorts first, as CompareStr orders it - got '+s);
end;

// an empty object is not on omitempty's list, any more than an empty record
procedure TVarDictTest.TestEmptyDictIsNotOmitted;
var
  r: TVariantHolder;
  s: string;
begin
  r.Doc:= VarDictCreate;
  Assert.AreEqual(JSONOK,JSON.Marshal(r,s));
  Assert.AreEqual('{"Doc":{}}',s);
end;

procedure TVarDictTest.TestEncodeRejectsMultiDimensionalArrays;
var
  v: Variant;
  s: string;
begin
  v:= VarArrayCreate([0,1,0,1],varVariant);
  v[0,0]:= 1;
  // there is no JSON shape for this that survives a round-trip, and claiming
  // success is how the empty-dictionary hole happened
  Assert.AreEqual(JSONUnsupportedType,JSON.Marshal(v,s));
end;

initialization
  TDUnitX.RegisterTestFixture(TVarDictTest);

end.
