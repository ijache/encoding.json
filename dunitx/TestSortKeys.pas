unit TestSortKeys;

// TJSONConfig.SortKeys: record and object members in sorted order. Two guards: a
// Configure flip reaches a type already cached, and the order is ordinal, so it
// is the same on every locale.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSortKeysTest = class
  public
    [Test] procedure TestDefaultIsDeclarationOrder;
    [Test] procedure TestSortedOrder;
    [Test] procedure TestSortsByEffectiveName;
    [Test] procedure TestOrderIsOrdinalNotAlphabetical;
    [Test] procedure TestShorterKeySortsFirst;
    [Test] procedure TestShorterKeySortsFirstEvenBeforeASpace;
    [Test] procedure TestTieKeepsDeclarationOrder;
    [Test] procedure TestNestedStructsSortAtEveryLevel;
    [Test] procedure TestOmitEmptyStillSkips;
    [Test] procedure TestClassPropertiesSortToo;
    [Test] procedure TestConfigureFlipTakesEffectOnAWarmCache;
    [Test] procedure TestDecodeIsUnaffected;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  encoding.json;

type
  // deliberately declared out of sorted order, so declaration order and
  // sorted order are never the same text
  TUnsorted = record
    Charlie: integer;
    Alpha: integer;
    Bravo: integer;
  end;

  // the attribute's name decides: Alpha is declared first and sorts last
  TRenamed = record
    [JSON('zulu')] Alpha: integer;
    [JSON('alpha')] Zulu: integer;
  end;

  // 'Z' is $5A and 'a' is $61, so ordinal order is Z before a. Every
  // case-insensitive or locale-aware compare puts a before Z.
  TCasing = record
    a: integer;
    Z: integer;
  end;

  // one key is a prefix of the other
  TPrefix = record
    AB: integer;
    A: integer;
  end;

  // a prefix followed by a space: sorting the escaped form "a b": would put it first
  TSpacedPrefix = record
    [JSON('a b')] X: integer;
    [JSON('a')] Y: integer;
  end;

  // two members whose effective name is the same. this compiles, and a stable
  // sort has to leave them in declaration order.
  TTied = record
    [JSON('same')] First: integer;
    [JSON('same')] Second: integer;
  end;

  TInner = record
    Yankee: integer;
    Xray: integer;
  end;

  TOuter = record
    Zulu: TInner;
    Alpha: TInner;
  end;

  TEmptyable = record
    Charlie: integer;
    [JSON('',true)] Bravo: string;
    Alpha: integer;
  end;

  TSortedClass = class
  private
    fZulu: integer;
    fAlpha: integer;
  public
    property Zulu: integer read fZulu write fZulu;
    property Alpha: integer read fAlpha write fAlpha;
  end;

// a TJSONCodec of its own per test: the global instance is shared, so configuring
// it here would leak into whatever runs next
function SortingJSON: TJSONCodec;
var
  cfg: TJSONConfig;
begin
  cfg:= JSONDefaultConfig;
  cfg.SortKeys:= true;
  result:= TJSONCodec.Create(cfg);
end;


procedure TSortKeysTest.TestDefaultIsDeclarationOrder;
var
  j: TJSONCodec;
  r: TUnsorted;
  s: string;
begin
  Assert.IsFalse(JSONDefaultConfig.SortKeys,'the default has to stay off');

  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    r.Charlie:= 1; r.Alpha:= 2; r.Bravo:= 3;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Charlie":1,"Alpha":2,"Bravo":3}',s);
  finally
    j.Free;
  end;
end;


procedure TSortKeysTest.TestSortedOrder;
var
  j: TJSONCodec;
  r: TUnsorted;
  s: string;
begin
  j:= SortingJSON;
  try
    r.Charlie:= 1; r.Alpha:= 2; r.Bravo:= 3;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Alpha":2,"Bravo":3,"Charlie":1}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestSortsByEffectiveName;
var
  j: TJSONCodec;
  r: TRenamed;
  s: string;
begin
  j:= SortingJSON;
  try
    r.Alpha:= 1; r.Zulu:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    // by wire name: "alpha", which carries Zulu's value, comes first. by
    // member name it would be the same two keys with 1 and 2 swapped.
    Assert.AreEqual('{"alpha":2,"zulu":1}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestOrderIsOrdinalNotAlphabetical;
var
  j: TJSONCodec;
  r: TCasing;
  s: string;
begin
  j:= SortingJSON;
  try
    r.a:= 1; r.Z:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Z":2,"a":1}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestShorterKeySortsFirst;
var
  j: TJSONCodec;
  r: TPrefix;
  s: string;
begin
  j:= SortingJSON;
  try
    r.AB:= 1; r.A:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"A":2,"AB":1}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestShorterKeySortsFirstEvenBeforeASpace;
var
  j: TJSONCodec;
  r: TSpacedPrefix;
  s: string;
begin
  j:= SortingJSON;
  try
    r.X:= 1; r.Y:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"a":2,"a b":1}',s,false);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestTieKeepsDeclarationOrder;
var
  j: TJSONCodec;
  r: TTied;
  s: string;
begin
  j:= SortingJSON;
  try
    r.First:= 1; r.Second:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    // an unstable sort is free to emit 2 before 1 here
    Assert.AreEqual('{"same":1,"same":2}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestNestedStructsSortAtEveryLevel;
var
  j: TJSONCodec;
  r: TOuter;
  s: string;
begin
  j:= SortingJSON;
  try
    r.Zulu.Yankee:= 1; r.Zulu.Xray:= 2;
    r.Alpha.Yankee:= 3; r.Alpha.Xray:= 4;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Alpha":{"Xray":4,"Yankee":3},"Zulu":{"Xray":2,"Yankee":1}}',s);
  finally
    j.Free;
  end;
end;


procedure TSortKeysTest.TestOmitEmptyStillSkips;
var
  j: TJSONCodec;
  r: TEmptyable;
  s: string;
begin
  j:= SortingJSON;
  try
    r.Charlie:= 1; r.Bravo:= ''; r.Alpha:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Alpha":2,"Charlie":1}',s,'skipped from the middle of the sorted run');

    r.Bravo:= 'x';
    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Alpha":2,"Bravo":"x","Charlie":1}',s);
  finally
    j.Free;
  end;
end;

procedure TSortKeysTest.TestClassPropertiesSortToo;
var
  j: TJSONCodec;
  o: TSortedClass;
  s: string;
begin
  j:= SortingJSON;
  o:= TSortedClass.Create;
  try
    o.Zulu:= 1; o.Alpha:= 2;
    Assert.AreEqual(JSONOK,j.Marshal(o,s));
    Assert.AreEqual('{"Alpha":2,"Zulu":1}',s);
  finally
    o.Free;
    j.Free;
  end;
end;

// the first Marshal caches the order unsorted; only Configure replacing the cache
// lets the flip reach it
procedure TSortKeysTest.TestConfigureFlipTakesEffectOnAWarmCache;
var
  cfg: TJSONConfig;
  j: TJSONCodec;
  r: TUnsorted;
  s: string;
begin
  j:= TJSONCodec.Create(JSONDefaultConfig);
  try
    r.Charlie:= 1; r.Alpha:= 2; r.Bravo:= 3;

    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Charlie":1,"Alpha":2,"Bravo":3}',s,'cache cold, sorting off');

    cfg:= JSONDefaultConfig;
    cfg.SortKeys:= true;
    j.Configure(cfg);

    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Alpha":2,"Bravo":3,"Charlie":1}',s,'cache warm, sorting on');
    Assert.IsTrue(j.Config.SortKeys,'Config reads back');

    // and back again, on the same warm cache
    cfg.SortKeys:= false;
    j.Configure(cfg);

    Assert.AreEqual(JSONOK,j.Marshal(r,s));
    Assert.AreEqual('{"Charlie":1,"Alpha":2,"Bravo":3}',s,'cache warm, sorting off again');
  finally
    j.Free;
  end;
end;


// SortKeys is an encode-side option only - it must not reach the parse path's
// key lookup, which stays order-independent
procedure TSortKeysTest.TestDecodeIsUnaffected;
var
  j: TJSONCodec;
  r: TUnsorted;
begin
  j:= SortingJSON;
  try
    r.Charlie:= 0; r.Alpha:= 0; r.Bravo:= 0;
    Assert.AreEqual(JSONOK,j.Unmarshal('{"Bravo":3,"Charlie":1,"Alpha":2}',r));
    Assert.AreEqual(1,r.Charlie);
    Assert.AreEqual(2,r.Alpha);
    Assert.AreEqual(3,r.Bravo);
  finally
    j.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSortKeysTest);

end.
